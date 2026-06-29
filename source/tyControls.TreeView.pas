unit tyControls.TreeView;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, Controls, Graphics, LCLType, LCLIntf, LazUTF8, ImgList,
  BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.ScrollBar,
  tyControls.TreeView.Columns, tyControls.Edit;

type
  { C4: hit-test result — which part of a node row the mouse landed in }
  TTyTreeHitPart = (hpNowhere, hpButton, hpImage, hpLabel, hpIndent,
                    hpHeaderSection, hpHeaderDivider,
                    hpCheckBox);   { B3: the checkbox slot in the main column }

  { B1: per-tree option flags (VTV-style set; default [] = ③a/③b behaviour) }
  { ③d B1: toVariableNodeHeight opts a tree into per-node row heights via
    OnMeasureItem (default off ⇒ every node uses DefaultNodeHeight, == ③c).
    ③d C1: toIncrementalSearch opts a tree into type-to-find: printable chars
    typed with focus on the tree jump focus to the next matching visible node
    (default off ⇒ typing does nothing special, == ③c).
    ③d D1: toOwnerDraw opts a tree into per-cell owner-draw via OnDrawNode (full
    cell-content replacement) + OnAfterCellPaint (overlay). Default off ⇒ the
    default cell content paints, == ③c.
    ③e E1: toEditable opts a tree into in-place cell editing via a themed TTyEdit
    overlay (F2 / double-click on an editable cell). Default off ⇒ no editing,
    == ③d. Appended last so the existing ordinals are undisturbed. }
  TTyTreeOption = (toMultiSelect, toCheckSupport, toFullRowSelect,
                   toAutoTristateTracking, toVariableNodeHeight,
                   toIncrementalSearch, toOwnerDraw, toEditable);
  TTyTreeOptions = set of TTyTreeOption;

  { A2: check column type for a node }
  TTyCheckType  = (ctNone, ctCheckBox, ctTriStateCheckBox, ctRadioButton);
  { A2: check state of a node }
  TTyCheckState = (csUnchecked, csChecked, csMixed);

type
  PTyTreeNode = ^TTyTreeNode;

  TTyNodeState = (nsInitialized, nsHasChildren, nsExpanded, nsVisible, nsSelected,
                  nsHeightMeasured, nsDeleting, nsClearing);
  TTyNodeStates = set of TTyNodeState;

  TTyNodeInitState = (ivsHasChildren, ivsExpanded, ivsSelected, ivsReInit);
  TTyNodeInitStates = set of TTyNodeInitState;

  TTyTreeNode = record
    Index, ChildCount: Cardinal;
    NodeHeight: Word;
    States: TTyNodeStates;
    TotalCount: Cardinal;       // self + all descendants
    TotalHeight: Cardinal;      // pixels of self + expanded/visible descendants
    Parent, PrevSibling, NextSibling, FirstChild, LastChild: PTyTreeNode;
    { A2/B1: per-node check column type and state (byte fields; zero-init by MakeNewNode) }
    CheckType:  TTyCheckType;   // ctNone by default
    CheckState: TTyCheckState;  // csUnchecked by default
    // user data blob (NodeDataSize bytes) follows at offset TreeNodeSize
  end;

  TTyTreeView = class;

  TTyTreeNodeEvent    = procedure(Sender: TTyTreeView; Node: PTyTreeNode) of object;
  TTyTreeChangingEvent = procedure(Sender: TTyTreeView; Node: PTyTreeNode; var Allowed: Boolean) of object;
  { C1: fired before a check-state change; set Allowed:=False to veto }
  TTyTreeCheckingEvent = procedure(Sender: TTyTreeView; Node: PTyTreeNode; var Allowed: Boolean) of object;
  TTyTreeInitNodeEvent     = procedure(Sender: TTyTreeView; ParentNode, Node: PTyTreeNode; var InitStates: TTyNodeInitStates) of object;
  TTyTreeInitChildrenEvent = procedure(Sender: TTyTreeView; Node: PTyTreeNode; var ChildCount: Cardinal) of object;
  TTyTreeGetTextEvent  = procedure(Sender: TTyTreeView; Node: PTyTreeNode; var Text: string) of object;
  { D2: column event — fired when a column is resized }
  TTyTreeColumnEvent = procedure(Sender: TTyTreeView; Column: Integer) of object;

  { D3: column reorder event — fired when a column is dragged to a new position }
  TTyTreeColumnReorderEvent = procedure(Sender: TTyTreeView;
    OldPosition, NewPosition: Integer) of object;

  { E1: compare event for the sort engine — app returns <0 / 0 / >0 (natural order;
    direction is handled internally by the sort). }
  TTyTreeCompareEvent = procedure(Sender: TTyTreeView;
    Node1, Node2: PTyTreeNode; Column: Integer; var CompareResult: Integer) of object;

  { ③e E2: inline-edit lifecycle events (mirror VTV's surface).
    OnEditing — fired before the editor opens; set Allowed:=False to veto (it
                defaults True). OnNewText — fired on commit ONLY when the text
                actually changed; the app writes NewText into its node blob.
                OnEditCancelled — fired on Esc / programmatic CancelEdit. }
  TTyTreeEditingEvent    = procedure(Sender: TTyTreeView; Node: PTyTreeNode;
    Column: Integer; var Allowed: Boolean) of object;
  TTyTreeNewTextEvent    = procedure(Sender: TTyTreeView; Node: PTyTreeNode;
    Column: Integer; const NewText: string) of object;
  TTyTreeColumnNodeEvent = procedure(Sender: TTyTreeView; Node: PTyTreeNode;
    Column: Integer) of object;

  { C3: text type (mirrors VTV's TVSTTextType) }
  TTyVSTTextType = (ttNormal, ttStatic);

  { C3: image kind (mirrors VTV's TVTImageKind) }
  TTyVTImageKind = (ikNormal, ikSelected, ikState, ikOverlay);

  { C3: OnGetImageIndex event }
  TTyTreeGetImageIndexEvent = procedure(Sender: TTyTreeView; Node: PTyTreeNode;
    Kind: TTyVTImageKind; Column: Integer; var Ghosted: Boolean;
    var ImageIndex: Integer) of object;

  { C3: OnGetText event with Column + TextType (full VTV signature) }
  TTyTreeGetTextWithTypeEvent = procedure(Sender: TTyTreeView; Node: PTyTreeNode;
    Column: Integer; TextType: TTyVSTTextType; var CellText: string) of object;

  { C3: OnPaintText — post-draw hook (no-op in ③a) }
  TTyTreePaintTextEvent = procedure(Sender: TTyTreeView; const TargetCanvas: TCanvas;
    Node: PTyTreeNode; Column: Integer; TextType: TTyVSTTextType) of object;

  { ③d B1: OnMeasureItem — fired once per node from InitNode (when
    toVariableNodeHeight is set) so the app can return a per-node row height.
    ANodeHeight is seeded with the node's current height (DefaultNodeHeight for a
    fresh node); the app overwrites it. ACanvas is the control canvas (for text
    measurement). Heights are LOGICAL pixels — device scaling happens at paint. }
  TTyTreeMeasureItemEvent = procedure(Sender: TTyTreeView; ACanvas: TCanvas;
    Node: PTyTreeNode; var ANodeHeight: Integer) of object;

  { ③d C1: OnIncrementalSearch — custom match predicate for type-to-find. Fired
    once per candidate visible node during the search walk; the app sets AMatch
    (seeded False) to True to accept the node. ASearchText is the accumulated
    type-ahead buffer. When unassigned, the default is a case-insensitive PREFIX
    test of ASearchText against the node's main-column text. }
  TTyTreeIncrementalSearchEvent = procedure(Sender: TTyTreeView;
    Node: PTyTreeNode; const ASearchText: string; var AMatch: Boolean) of object;

  { ③d D1: per-cell owner-draw events (cross-platform post-EndPaint subset).
    Both fire AFTER the BGRA layer has been composited onto ACanvas, with
    ACanvas (the control canvas) clipped to the cell's device rect (ACellRect,
    the exact rect GetCellRect(Node, Column) returns).

    OnDrawNode — FULL cell-content replacement. Fires only when toOwnerDraw is in
    Options. When assigned, RenderTo SKIPS the default cell content (caption text,
    and for the main column the node image) for that cell; the row background and
    tree chrome (expand button / tree-lines / checkbox) still paint underneath.
    The app draws the entire cell content here.

    OnAfterCellPaint — overlay. Fires for EVERY painted cell (independent of
    toOwnerDraw), on top of the default content AND any OnDrawNode result. Use it
    to decorate cells (badges, focus rings, etc.); no-op the cells you don't care
    about.

    DEFERRED (NOT implemented in ③d D1): OnBeforeCellPaint (a backdrop UNDER the
    default text) — it cannot be done post-EndPaint and needs a temp-bitmap→BGRA
    path. }
  TTyTreeDrawNodeEvent  = procedure(Sender: TTyTreeView; ACanvas: TCanvas;
    Node: PTyTreeNode; Column: Integer; const ACellRect: TRect) of object;
  TTyTreeCellPaintEvent = procedure(Sender: TTyTreeView; ACanvas: TCanvas;
    Node: PTyTreeNode; Column: Integer; const ACellRect: TRect) of object;

const
  TreeNodeSize = (SizeOf(TTyTreeNode) + 7) and not 7;  // pointer-aligned struct stride
  { B3: one cache mark per TREE_CACHE_STEP visible nodes.
    A flat 200k-node list will have ~100 marks; a GetNodeAt near the end
    walks at most TREE_CACHE_STEP nodes after finding the nearest mark. }
  TREE_CACHE_STEP = 2000;

type
  { B3: one position-cache mark }
  TTyTreeCacheMark = record
    Node:    PTyTreeNode;
    NodeTop: Integer;   // absolute Y of Node.NodeHeight's top pixel
  end;

  TTyTreeView = class(TTyCustomControl)
  private
    FRoot: PTyTreeNode;
    FNodeDataSize: Integer;     // -1 until set
    FNodeAllocSize: Integer;    // TreeNodeSize + Max(0, FNodeDataSize)
    FDefaultNodeHeight: Integer;
    FOnFreeNode: TTyTreeNodeEvent;
    { B1 scroll engine }
    FCacheValid: Boolean;
    FRangeY:    Integer;
    { B3 position cache }
    FPositionCache: array of TTyTreeCacheMark;
    { B3 debug/test counter: number of nodes visited in the most-recent GetNodeAt walk.
      Reset to 0 at the start of each GetNodeAt call; exposed read-only for tests. }
    FLastGetNodeAtVisits: Integer;
    { A5 events }
    FOnInitNode:     TTyTreeInitNodeEvent;
    FOnInitChildren: TTyTreeInitChildrenEvent;
    FOnExpanding:    TTyTreeChangingEvent;
    FOnExpanded:     TTyTreeNodeEvent;
    FOnCollapsing:   TTyTreeChangingEvent;
    FOnCollapsed:    TTyTreeNodeEvent;
    { C1: selection + focus }
    FFocusedNode:    PTyTreeNode;
    FSelectedNode:   PTyTreeNode;
    FOnChange:       TTyTreeNodeEvent;
    FOnFocusChanged: TTyTreeNodeEvent;
    { C1: check events }
    FOnChecking:     TTyTreeCheckingEvent;
    FOnChecked:      TTyTreeNodeEvent;
    { D1: selection-changed event (fired once per gesture when multi-select set changes) }
    FOnSelectionChanged: TNotifyEvent;
    { A3: multi-select count + range anchor }
    FSelectionCount: Integer;
    FRangeAnchor:    PTyTreeNode;
    { C3: paint-related fields }
    FHotNode:              PTyTreeNode;   // node under cursor (HotTrack); nil = none
    FOnGetText:            TTyTreeGetTextEvent;
    FOnGetImageIndex:      TTyTreeGetImageIndexEvent;
    FOnGetTextWithType:    TTyTreeGetTextWithTypeEvent;
    FOnPaintText:          TTyTreePaintTextEvent;
    { ③d B1: variable per-node row height }
    FOnMeasureItem:        TTyTreeMeasureItemEvent;
    { ③d C1: incremental type-to-find search }
    FOnIncrementalSearch:  TTyTreeIncrementalSearchEvent;
    { ③d D1: per-cell owner-draw (post-EndPaint; cross-platform) }
    FOnDrawNode:           TTyTreeDrawNodeEvent;
    FOnAfterCellPaint:     TTyTreeCellPaintEvent;
    { C4: interaction events }
    FOnNodeClick:          TTyTreeNodeEvent;
    FOnNodeDblClick:       TTyTreeNodeEvent;
    { C4: DblClick tracking — remember which node the MouseDown landed on }
    FLastMouseNode:        PTyTreeNode;
    { ③e E1: inline cell editing. One persistent hidden TTyEdit overlay, created
      in the ctor, repositioned + shown on demand (reused for every edit). Edit
      state lives on the control (no node-record growth). FEditing is declared in
      the protected section (it doubles as the incremental-search suppression
      hook) — only the remaining state fields live here.
        FEditOriginalText — the cell text at edit start (OnNewText fires iff
                            FEditor.Text differs at commit).
        FEndingEdit       — reentrancy guard shared by commit/cancel/focus-loss so
                            they can't recurse or double-fire.
        FLastMouseColumn  — column under the last MouseDown (NoColumn = none); F2
                            uses it (fallback: MainColumn, else 0). Reused by ③f.
        FLastMouseHitPart — the hit part under the last MouseDown; DblClick uses it
                            to decide edit-vs-toggle (E3: edit only on an editable
                            cell region — hpLabel/hpImage, not button/checkbox). }
    FEditor:               TTyEdit;
    FEditNode:             PTyTreeNode;
    FEditColumn:           Integer;
    FEditOriginalText:     string;
    FEndingEdit:           Boolean;
    FLastMouseColumn:      Integer;
    FLastMouseHitPart:     TTyTreeHitPart;
    { ③e E2: inline-edit events }
    FOnEditing:            TTyTreeEditingEvent;
    FOnNewText:            TTyTreeNewTextEvent;
    FOnEditCancelled:      TTyTreeColumnNodeEvent;
    { C1: layout / display properties }
    FIndent:            Integer;
    FImages:            TImageList;
    FEmptyListMessage:  string;
    FShowButtons:       Boolean;
    FShowTreeLines:     Boolean;
    FShowRoot:          Boolean;
    FToggleOnDblClick:  Boolean;
    FHotTrack:          Boolean;
    { C2: embedded scrollbars + offsets }
    FVScroll:   TTyScrollBar;   // vertical; created in constructor (never nil after Create)
    FHScroll:   TTyScrollBar;   // horizontal; created in constructor (never nil after Create)
    FOffsetY:   Integer;        // ≤ 0; how many pixels the viewport is scrolled down
    FOffsetX:   Integer;        // ≤ 0; how many pixels the viewport is scrolled right
    FRangeX:    Integer;        // max content width; accumulated by paint pass (C3); reset to 0 by InvalidateTreeLayout on every structural change
    FSyncingScroll: Boolean;    // reentrancy guard (mirrors ListBox pattern)
    { B (columns): header sub-object }
    FHeader:    TTyTreeHeader;
    { D2: column resize state }
    FResizeColumn:     Integer;   // NoColumn when not resizing
    FResizeStartWidth: Integer;   // col.Width at drag start (logical px)
    FResizeStartX:     Integer;   // X at drag start (device px)
    FOnColumnResized:  TTyTreeColumnEvent;
    { D3: column drag-reorder state }
    FDragColumn:       Integer;   // collection Index of the dragged column; NoColumn when idle
    FDragPending:      Boolean;   // MouseDown on a draggable section; drag not yet started
    FDragStartX:       Integer;   // device X at the drag press
    FDragging:         Boolean;   // threshold exceeded: ghost + drop-mark active
    FDragTargetPos:    Integer;   // visual position to drop into (0-based)
    FOnColumnReorder:  TTyTreeColumnReorderEvent;
    { E1/E2/E3: sort engine }
    FOnCompareNodes:   TTyTreeCompareEvent;
    FOnHeaderClick:    TTyTreeColumnEvent;
    FSorting:          Boolean;   // reentrancy guard: SortTree -> HeaderChanged -> SortTree
    FSortedColumn:     Integer;   // last key SortTree ran with — so a width/reorder
    FSortedDirection:  TTySortDirection;  //   change (same key) does NOT re-sort the tree
    { B1: tree option flags }
    FOptions:          TTyTreeOptions;
    procedure SetOptions(AValue: TTyTreeOptions);
    { ③d B1: per-node row-height accessors (variable height) }
    function  GetNodeHeight(Node: PTyTreeNode): Integer;
    procedure SetNodeHeight(Node: PTyTreeNode; AValue: Integer);
    { ③d C1: incremental-search internals }
    function  GetNodeSearchText(Node: PTyTreeNode): string;        // main-column text (mirrors the caption)
    function  NodeMatchesSearch(Node: PTyTreeNode; const ASearchText: string): Boolean;
    procedure DoIncrementalSearch;                                 // walk visible nodes from focus (wrapping)
    { B1: check property raw accessors }
    function  GetCheckType(Node: PTyTreeNode): TTyCheckType;
    procedure SetCheckType(Node: PTyTreeNode; AValue: TTyCheckType);
    function  GetCheckState(Node: PTyTreeNode): TTyCheckState;
    procedure SetCheckState(Node: PTyTreeNode; AValue: TTyCheckState);
    function  GetChecked(Node: PTyTreeNode): Boolean;
    procedure SetChecked(Node: PTyTreeNode; AValue: Boolean);
    { E3: internal — process a header section click (toggle sort direction / set sort column) }
    procedure _HandleHeaderClick(ColIndex: Integer);
    procedure VScrollChange(Sender: TObject);
    procedure HScrollChange(Sender: TObject);
    procedure UpdateScrollBars;
    { B (columns): header/column change handler }
    procedure HeaderChanged(Sender: TObject);
    procedure SetHeader(AValue: TTyTreeHeader);
    procedure SetIndent(AValue: Integer);
    procedure SetImages(AValue: TImageList);
    procedure SetShowButtons(AValue: Boolean);
    procedure SetShowTreeLines(AValue: Boolean);
    procedure SetShowRoot(AValue: Boolean);
    procedure SetToggleOnDblClick(AValue: Boolean);
    procedure SetHotTrack(AValue: Boolean);
    { C1: selection internals }
    procedure ClearSelectedNode;
    { FIX 3: recursive full-tree clear of nsSelected (walks collapsed subtrees) }
    procedure ClearAllSelectedFull(ANode: PTyTreeNode);
    function  GetSelected(Node: PTyTreeNode): Boolean;
    procedure SetSelected(Node: PTyTreeNode; AValue: Boolean);
    function  GetFocusedNode: PTyTreeNode;
    procedure SetFocusedNode(AValue: PTyTreeNode);
    { D1: move focus without touching selection (multi-select helper) }
    procedure MoveFocusOnly(AValue: PTyTreeNode);
    { D1: Ctrl+Shift additive range extension — add anchor..target to current selection }
    procedure AddRangeToSelection(AAnchor, ATarget: PTyTreeNode);
    function  MakeNewNode: PTyTreeNode;
    procedure FreeNodeMem(Node: PTyTreeNode);
    procedure SetNodeDataSize(AValue: Integer);
    function  GetRootNodeCount: Cardinal;
    procedure SetRootNodeCount(AValue: Cardinal);
    procedure AdjustTotalCount(Node: PTyTreeNode; Delta: Integer);
    procedure AdjustTotalHeight(Node: PTyTreeNode; Delta: Integer);
    procedure InvalidateTreeLayout;
    { B3 position-cache helpers }
    procedure ValidateCache;
    function  FindInCache(Y: Integer): Integer;
    { ③d A1: shared cell-geometry — given the device content rect CR, the device
      row top/height of a node's row and a column index, produce the cell's device
      rect. Single source of the per-column x-math used by BOTH RenderTo (paint)
      and GetCellRect (measure) so they can never drift. Column = -1 or the
      MainColumn maps to the main cell; in 0-column mode Column is ignored and the
      cell spans CR.Left..CR.Right. Returns False only when a real column index is
      out of range / not visible. }
    function  InternalCellRect(const CR: TRect; ARowTop, ARowH, AColumn, APPI: Integer;
                out ACellRect: TRect): Boolean;
    { A5 helpers }
    function  ComputeExpandedSubtreeHeight(Node: PTyTreeNode): Integer;
    function  GetExpanded(Node: PTyTreeNode): Boolean;
    procedure SetExpanded(Node: PTyTreeNode; AValue: Boolean);
  protected
    { ③d C1: incremental type-to-find state. Protected (not private) so tests can
      drive/inspect it via a descendant; FEditing is also the ③e edit-suppression
      hook (always False until ③e wires inline editing). }
    FSearchBuffer:         string;     // accumulated type-ahead chars
    FSearchLastTick:       QWord;      // GetTickCount64 of the last accepted char
    FSearchTimeout:        Integer;    // ms of idle before the buffer auto-resets
    FEditing:              Boolean;    // True while an inline editor is active (③e)
    { ③e E2: inline-edit internals. Protected so a descendant / test can reach the
      editor + geometry helper without growing the public surface.
      EditorBoundsFromCell insets the device cell rect to where the caption was
      drawn (via CellTextRect — the indent + checkbox + image slots in the main
      column, the flat text pad elsewhere); CurrentCellText reads the cell text
      via the SAME path the painter uses (OnGetTextWithType / OnGetText,
      Column-aware) so the editor seeds with exactly what's on screen; FinishEdit
      hides + clears the edit state. }
    function  CellTextRect(Node: PTyTreeNode; Column: Integer; const ACellRect: TRect): TRect;
    function  EditorBoundsFromCell(Node: PTyTreeNode; Column: Integer; const r: TRect): TRect;
    function  CurrentCellText(Node: PTyTreeNode; Column: Integer): string;
    procedure FinishEdit;
    { ③e E4: keep the editor glued to its cell as the view changes (called from
      every layout/scroll path) and the editor's own input handlers (Enter/Esc on
      FEditor.OnKeyDown, focus-loss commit on FEditor.OnExit). Protected so a
      descendant / test can drive them without a real window handle. }
    procedure RepositionEditor;
    procedure EditorKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure EditorExit(Sender: TObject);
    property  InlineEditor: TTyEdit read FEditor;   // child editor (tests/descendants)
    { E3: the column recorded by the last MouseDown (NoColumn = none). Protected so
      a descendant / test can inspect the trigger state without growing the public
      surface; F2 uses it as the effective edit column. }
    property  LastMouseColumn: Integer read FLastMouseColumn;
    function GetStyleTypeKey: string; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure Paint; override;
    function  DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
                MousePos: TPoint): Boolean; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DblClick; override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    { ③d C1: LCL delivers printable chars here (after KeyDown). When
      toIncrementalSearch is set we accumulate them into FSearchBuffer and jump
      focus to the next matching visible node. }
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor  Destroy; override;
    function  GetNodeData(Node: PTyTreeNode): Pointer;
    procedure SetChildCount(Node: PTyTreeNode; NewCount: Cardinal);
    function  AddChild(AParent: PTyTreeNode): PTyTreeNode;
    procedure DeleteNode(Node: PTyTreeNode);
    procedure Clear;
    { A5 lifecycle }
    procedure InitNode(Node: PTyTreeNode);
    procedure InitChildren(Node: PTyTreeNode);
    procedure ToggleNode(Node: PTyTreeNode; AExpand: Boolean);
    { C1: toggle a node's check state, fire OnChecking/OnChecked, propagate if needed }
    procedure ToggleCheck(Node: PTyTreeNode);
    { A5 iterators }
    function GetFirstChild(Node: PTyTreeNode): PTyTreeNode;
    function GetLastChild(Node: PTyTreeNode): PTyTreeNode;
    function GetNextSibling(Node: PTyTreeNode): PTyTreeNode;
    function GetPrevSibling(Node: PTyTreeNode): PTyTreeNode;
    function GetParent(Node: PTyTreeNode): PTyTreeNode;
    function GetNodeLevel(Node: PTyTreeNode): Integer;
    function GetFirst: PTyTreeNode;
    function GetNext(Node: PTyTreeNode): PTyTreeNode;
    function GetFirstVisibleNoInit: PTyTreeNode;
    function GetNextVisibleNoInit(Node: PTyTreeNode): PTyTreeNode;
    function GetPreviousVisibleNoInit(Node: PTyTreeNode): PTyTreeNode;
    { B2/B3 scroll engine }
    function  GetNodeAt(Y: Integer; out ANodeTop: Integer): PTyTreeNode;
    { B1 helpers — used by tests + scroll engine }
    function  SumVisibleHeights: Integer;
    { A2: check-propagation pure helpers }
    procedure PropagateCheckDown(Node: PTyTreeNode; AState: TTyCheckState);
    function  RecomputeParentCheckState(Node: PTyTreeNode): TTyCheckState;
    { A3: range-selection helper + selection-count }
    procedure InternalSetSelected(Node: PTyTreeNode; AValue: Boolean);
    procedure SelectRange(AAnchor, ATarget: PTyTreeNode);
    function  SelectedCount: Integer;
    { D1: multi-select public API }
    procedure SelectAll;
    function  GetFirstSelected: PTyTreeNode;
    function  GetNextSelected(Node: PTyTreeNode): PTyTreeNode;
    { C1: selection + focus }
    procedure ClearSelection;
    procedure FullExpand(Node: PTyTreeNode = nil);
    procedure FullCollapse(Node: PTyTreeNode = nil);
    procedure ScrollIntoView(Node: PTyTreeNode);
    property Expanded[Node: PTyTreeNode]: Boolean read GetExpanded write SetExpanded;
    property Selected[Node: PTyTreeNode]: Boolean read GetSelected write SetSelected;
    property FocusedNode: PTyTreeNode read GetFocusedNode write SetFocusedNode;
    { B1: raw per-node check accessors (no propagation — that is Phase C) }
    property CheckType[Node: PTyTreeNode]: TTyCheckType   read GetCheckType  write SetCheckType;
    property CheckState[Node: PTyTreeNode]: TTyCheckState  read GetCheckState write SetCheckState;
    property Checked[Node: PTyTreeNode]: Boolean           read GetChecked    write SetChecked;
    { ③d B1: per-node row height (logical px). Reading returns Node^.NodeHeight;
      writing applies the delta via AdjustTotalHeight + marks the node measured +
      invalidates the layout. Programmatic override (mirrors VTV SetNodeHeight). }
    property NodeHeight[Node: PTyTreeNode]: Integer        read GetNodeHeight write SetNodeHeight;
    property RootNode: PTyTreeNode read FRoot;
    property RangeY: Integer read FRangeY;
    property OffsetY: Integer read FOffsetY;
    property OffsetX: Integer read FOffsetX;
    property RangeX: Integer read FRangeX;
    { C2: read-only access to the embedded scrollbars (for tests + C3 paint). }
    property VScroll: TTyScrollBar read FVScroll;
    property HScroll: TTyScrollBar read FHScroll;
    { C2: content geometry helpers used by C3 paint pass. }
    function ContentHeight: Integer;
    function ContentRect: TRect;
    { ③d A1: cell geometry — the device-pixel rect of Node's cell in Column,
      in the SAME coordinate space RenderTo paints into (ContentRect space).
      Accounts for FOffsetX/FOffsetY, the header-band top inset, the per-column
      left/width (multi-column) and HiDPI. Column = -1 (or = Header.MainColumn)
      returns the main/whole cell; in 0-column mode Column is ignored and the
      cell is the content row rect (CR.Left..CR.Right). Returns False when Node
      is not currently visible (nil, root, under a collapsed ancestor, or its
      row is scrolled entirely outside the content rect). Has no side effects on
      node state (never calls InitNode). RenderTo derives its per-cell rect from
      the same shared helper so paint and GetCellRect cannot drift. }
    function GetCellRect(Node: PTyTreeNode; Column: Integer; out ACellRect: TRect): Boolean;
    { C3: paint }
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    { B3: read-only; how many nodes were visited in the last GetNodeAt walk (for perf tests) }
    property LastGetNodeAtVisits: Integer read FLastGetNodeAtVisits;
    { C4: hit-testing }
    function GetNodeAtPoint(X, Y: Integer; out APart: TTyTreeHitPart): PTyTreeNode; overload;
    { D1: 3-out overload — also returns the column index under the cursor }
    function GetNodeAtPoint(X, Y: Integer; out APart: TTyTreeHitPart; out AColumn: Integer): PTyTreeNode; overload;
    { D1: header hit-test — True when (X,Y) is in the header band }
    function GetHeaderHitAt(X, Y: Integer; out APart: TTyTreeHitPart; out AColumn: Integer): Boolean;
    { E1: compare helper wrapping OnCompareNodes — returns 0 when unassigned }
    function DoCompare(Node1, Node2: PTyTreeNode; Column: Integer): Integer;
    { E1: sort the direct children of Node (one level only) }
    procedure Sort(Node: PTyTreeNode; Column: Integer; ADirection: TTySortDirection; DoInit: Boolean);
    { E2: recursive sort of the whole tree (initialized+expanded levels only) }
    procedure SortTree(Column: Integer; ADirection: TTySortDirection);
    { ③e E1: inline-edit public API (mirrors VirtualTreeView). E1 ships stubs;
      E2 fills the lifecycle. EditNode returns False when editing is not allowed
      (not toEditable, OnEditing veto, nil node, or the cell has no visible rect);
      EndEditNode commits (fires OnNewText iff the text changed), CancelEdit
      discards (fires OnEditCancelled). }
    function  EditNode(Node: PTyTreeNode; Column: Integer): Boolean;
    procedure EndEditNode;
    procedure CancelEdit;
    { ③e E1: read-only edit state. }
    property IsEditing:    Boolean     read FEditing;
    property EditedNode:   PTyTreeNode read FEditNode;
    property EditedColumn: Integer     read FEditColumn;
  published
    { B1: option flags set (default [] = ③a/③b behaviour) }
    property Options: TTyTreeOptions read FOptions write SetOptions default [];
    { B (columns): header sub-object }
    property Header: TTyTreeHeader read FHeader write SetHeader;
    property NodeDataSize: Integer read FNodeDataSize write SetNodeDataSize default -1;
    property DefaultNodeHeight: Integer read FDefaultNodeHeight write FDefaultNodeHeight default 18;
    property RootNodeCount: Cardinal read GetRootNodeCount write SetRootNodeCount default 0;
    { C1: display properties }
    property Indent: Integer read FIndent write SetIndent default 16;
    property Images: TImageList read FImages write SetImages;
    property EmptyListMessage: string read FEmptyListMessage write FEmptyListMessage;
    property ShowButtons: Boolean read FShowButtons write SetShowButtons default True;
    property ShowTreeLines: Boolean read FShowTreeLines write SetShowTreeLines default True;
    property ShowRoot: Boolean read FShowRoot write SetShowRoot default True;
    property ToggleOnDblClick: Boolean read FToggleOnDblClick write SetToggleOnDblClick default True;
    property HotTrack: Boolean read FHotTrack write SetHotTrack default False;
    { ③d C1: ms of keyboard idle before the incremental-search buffer auto-resets
      (next printable char starts a fresh search). Default 1000. }
    property SearchTimeout: Integer read FSearchTimeout write FSearchTimeout default 1000;
    { C1: re-published standard LCL properties }
    property Align;
    property Anchors;
    property Font;
    property StyleClass;
    property Controller;
    property TabStop default True;
    { events }
    property OnFreeNode:      TTyTreeNodeEvent         read FOnFreeNode      write FOnFreeNode;
    property OnInitNode:      TTyTreeInitNodeEvent     read FOnInitNode      write FOnInitNode;
    property OnInitChildren:  TTyTreeInitChildrenEvent read FOnInitChildren  write FOnInitChildren;
    property OnExpanding:     TTyTreeChangingEvent     read FOnExpanding     write FOnExpanding;
    property OnExpanded:      TTyTreeNodeEvent         read FOnExpanded      write FOnExpanded;
    property OnCollapsing:    TTyTreeChangingEvent     read FOnCollapsing    write FOnCollapsing;
    property OnCollapsed:     TTyTreeNodeEvent         read FOnCollapsed     write FOnCollapsed;
    property OnChange:        TTyTreeNodeEvent         read FOnChange        write FOnChange;
    property OnFocusChanged:  TTyTreeNodeEvent         read FOnFocusChanged  write FOnFocusChanged;
    { C1: check events }
    property OnChecking: TTyTreeCheckingEvent          read FOnChecking      write FOnChecking;
    property OnChecked:  TTyTreeNodeEvent              read FOnChecked       write FOnChecked;
    { D1: selection-changed event — fired once per gesture when multi-select set changes }
    property OnSelectionChanged: TNotifyEvent          read FOnSelectionChanged write FOnSelectionChanged;
    property OnNodeClick:     TTyTreeNodeEvent         read FOnNodeClick     write FOnNodeClick;
    property OnNodeDblClick:  TTyTreeNodeEvent         read FOnNodeDblClick  write FOnNodeDblClick;
    { C3: paint events }
    property OnGetText:            TTyTreeGetTextEvent           read FOnGetText            write FOnGetText;
    property OnGetTextWithType:    TTyTreeGetTextWithTypeEvent   read FOnGetTextWithType    write FOnGetTextWithType;
    property OnGetImageIndex:      TTyTreeGetImageIndexEvent     read FOnGetImageIndex      write FOnGetImageIndex;
    property OnPaintText:          TTyTreePaintTextEvent         read FOnPaintText          write FOnPaintText;
    { ③d D1: per-cell owner-draw — full replacement (gated by toOwnerDraw) + overlay }
    property OnDrawNode:           TTyTreeDrawNodeEvent          read FOnDrawNode           write FOnDrawNode;
    property OnAfterCellPaint:     TTyTreeCellPaintEvent         read FOnAfterCellPaint     write FOnAfterCellPaint;
    { ③d B1: per-node measure event — fired from InitNode when toVariableNodeHeight set }
    property OnMeasureItem:        TTyTreeMeasureItemEvent       read FOnMeasureItem        write FOnMeasureItem;
    { ③d C1: custom incremental-search match predicate (default = prefix match) }
    property OnIncrementalSearch:  TTyTreeIncrementalSearchEvent read FOnIncrementalSearch  write FOnIncrementalSearch;
    { D2: column resize event }
    property OnColumnResized: TTyTreeColumnEvent read FOnColumnResized write FOnColumnResized;
    { D3: column reorder event }
    property OnColumnReorder: TTyTreeColumnReorderEvent read FOnColumnReorder write FOnColumnReorder;
    { E1: sort compare event }
    property OnCompareNodes: TTyTreeCompareEvent read FOnCompareNodes write FOnCompareNodes;
    { E3: header click event (fired after sort, if sort was triggered) }
    property OnHeaderClick: TTyTreeColumnEvent read FOnHeaderClick write FOnHeaderClick;
    { ③e E2: inline-edit lifecycle events }
    property OnEditing:       TTyTreeEditingEvent    read FOnEditing       write FOnEditing;
    property OnNewText:       TTyTreeNewTextEvent    read FOnNewText       write FOnNewText;
    property OnEditCancelled: TTyTreeColumnNodeEvent read FOnEditCancelled write FOnEditCancelled;
  end;

implementation

{ TTyTreeView }

function TTyTreeView.GetStyleTypeKey: string;
begin
  Result := 'TyTreeView';
end;

procedure TTyTreeView.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FImages) then FImages := nil;
end;

{ ── C1 ── selection / focus ────────────────────────────────────────────────── }

{ ClearSelectedNode: internal — removes nsSelected from the currently-selected
  node without firing any event.  Used by SetSelected before setting a new node. }
procedure TTyTreeView.ClearSelectedNode;
begin
  if FSelectedNode = nil then Exit;
  Exclude(FSelectedNode^.States, nsSelected);
  if FSelectionCount > 0 then Dec(FSelectionCount);  { A3: keep count consistent }
  FSelectedNode := nil;
end;

function TTyTreeView.GetSelected(Node: PTyTreeNode): Boolean;
begin
  Result := (Node <> nil) and (Node <> FRoot) and (nsSelected in Node^.States);
end;

{ SetSelected — single-select semantics:
  * Deselect the previously-selected node.
  * Set nsSelected on the new node (if AValue=True) or just clear (AValue=False).
  * Fire OnChange once IFF the selection set actually changed. }
procedure TTyTreeView.SetSelected(Node: PTyTreeNode; AValue: Boolean);
var
  didChange: Boolean;
begin
  if (Node = nil) or (Node = FRoot) then Exit;

  if AValue then
  begin
    // Selecting a node: changed if the node is not already the selected one.
    didChange := (FSelectedNode <> Node);
    if not didChange then Exit;   // same node, same state — fire nothing
    ClearSelectedNode;             // deselects previous (adjusts FSelectionCount)
    Include(Node^.States, nsSelected);
    FSelectedNode := Node;
    Inc(FSelectionCount);          { A3: count the new selection }
  end
  else
  begin
    // Deselecting: changed only if this node was the selected one.
    if not (nsSelected in Node^.States) then Exit;
    didChange := True;
    Exclude(Node^.States, nsSelected);
    if FSelectedNode = Node then FSelectedNode := nil;
    if FSelectionCount > 0 then Dec(FSelectionCount);  { A3: keep count consistent }
  end;

  if didChange and Assigned(FOnChange) then
    FOnChange(Self, Node);
  Invalidate;
end;

{ ClearAllSelectedFull — FIX 3 helper: walk the ENTIRE structural tree
  (not just visible nodes) clearing nsSelected on every node.  This ensures
  that selected descendants hidden under a collapsed parent are also cleared,
  preventing stale highlights on re-expand and FSelectionCount desync. }
procedure TTyTreeView.ClearAllSelectedFull(ANode: PTyTreeNode);
var
  child: PTyTreeNode;
begin
  if ANode = nil then Exit;
  child := ANode^.FirstChild;
  while child <> nil do
  begin
    if nsSelected in child^.States then
      Exclude(child^.States, nsSelected);
    if child^.FirstChild <> nil then
      ClearAllSelectedFull(child);
    child := child^.NextSibling;
  end;
end;

{ ClearSelection: public — deselects all selected nodes, fires OnChange once.
  FIX 3: uses ClearAllSelectedFull (full structural walk, not just visible
  nodes) so selected nodes hidden under a collapsed parent are also cleared.
  This prevents stale highlights on re-expand and FSelectionCount desync. }
procedure TTyTreeView.ClearSelection;
var
  prev: PTyTreeNode;
begin
  if (FSelectedNode = nil) and (FSelectionCount = 0) then Exit;
  prev := FSelectedNode;
  // Walk the entire structural tree, not just visible nodes (FIX 3).
  ClearAllSelectedFull(FRoot);
  FSelectedNode   := nil;
  FSelectionCount := 0;
  if prev <> nil then
    if Assigned(FOnChange) then FOnChange(Self, prev)
  else
    if Assigned(FOnChange) then FOnChange(Self, nil);
  Invalidate;
end;

{ ── A2 ── check propagation pure helpers ─────────────────────────────────── }

{ PropagateCheckDown — sets every ALREADY-INITIALISED descendant whose
  CheckType is ctCheckBox or ctTriStateCheckBox to AState.  ctNone and
  ctRadioButton nodes are skipped.  Lazy (not-yet-initialised) subtrees are
  intentionally untouched — they will inherit the right state when they are
  eventually initialised in Phase B/C. }
procedure TTyTreeView.PropagateCheckDown(Node: PTyTreeNode; AState: TTyCheckState);
var
  child: PTyTreeNode;
begin
  if Node = nil then Exit;
  child := Node^.FirstChild;
  while child <> nil do
  begin
    if child^.CheckType in [ctCheckBox, ctTriStateCheckBox] then
      child^.CheckState := AState;
    // Recurse into already-initialised children (lazy-safe: only if FirstChild ≠ nil)
    if child^.FirstChild <> nil then
      PropagateCheckDown(child, AState);
    child := child^.NextSibling;
  end;
end;

{ RecomputeParentCheckState — inspect Node's direct check-children
  (ctCheckBox/ctTriStateCheckBox only; ctRadioButton/ctNone ignored).
  Returns: csChecked if all check-children are csChecked;
           csUnchecked if all are csUnchecked;
           csMixed if mixed or any is already csMixed;
           Node^.CheckState unchanged when there are no check-children. }
function TTyTreeView.RecomputeParentCheckState(Node: PTyTreeNode): TTyCheckState;
var
  child:        PTyTreeNode;
  hasChecked:   Boolean;
  hasUnchecked: Boolean;
begin
  Result       := Node^.CheckState;  // default: no change when no check-children
  hasChecked   := False;
  hasUnchecked := False;

  child := Node^.FirstChild;
  while child <> nil do
  begin
    if child^.CheckType in [ctCheckBox, ctTriStateCheckBox] then
    begin
      case child^.CheckState of
        csChecked:   hasChecked   := True;
        csUnchecked: hasUnchecked := True;
        csMixed:     begin Result := csMixed; Exit; end;  // short-circuit
      end;
      if hasChecked and hasUnchecked then begin Result := csMixed; Exit; end;
    end;
    child := child^.NextSibling;
  end;

  if hasChecked and not hasUnchecked then
    Result := csChecked
  else if hasUnchecked and not hasChecked then
    Result := csUnchecked;
  // else: no check-children → leave Result as Node^.CheckState
end;

{ ── A3 ── range-selection pure helpers ───────────────────────────────────── }

{ InternalSetSelected — add/remove nsSelected AND keep FSelectionCount correct.
  Never touches FRoot.  Only counts real transitions (no double-counts). }
procedure TTyTreeView.InternalSetSelected(Node: PTyTreeNode; AValue: Boolean);
begin
  if (Node = nil) or (Node = FRoot) then Exit;
  if AValue then
  begin
    if not (nsSelected in Node^.States) then
    begin
      Include(Node^.States, nsSelected);
      Inc(FSelectionCount);
      if FSelectedNode = nil then FSelectedNode := Node;  // maintain single-select field
    end;
  end
  else
  begin
    if nsSelected in Node^.States then
    begin
      Exclude(Node^.States, nsSelected);
      if FSelectionCount > 0 then Dec(FSelectionCount);
      if FSelectedNode = Node then FSelectedNode := nil;
    end;
  end;
end;

{ SelectRange — clear all selected nodes, then select every visible node from
  AAnchor to ATarget inclusive (order-independent: works in both directions).
  Maintains FSelectionCount. }
procedure TTyTreeView.SelectRange(AAnchor, ATarget: PTyTreeNode);
var
  n:       PTyTreeNode;
  inRange: Boolean;
begin
  if (AAnchor = nil) or (ATarget = nil) then Exit;

  // FIX 3: clear the FULL structural tree (not just visible) so selected nodes
  // hidden under collapsed parents don't persist as stale highlights.
  ClearAllSelectedFull(FRoot);
  FSelectionCount := 0;
  FSelectedNode   := nil;

  // Walk visible order: enter range when we hit either endpoint;
  // exit (and include the second endpoint) when we hit the other one.
  inRange := False;
  n := GetFirstVisibleNoInit;
  while n <> nil do
  begin
    if (n = AAnchor) or (n = ATarget) then
    begin
      if not inRange then
      begin
        // First endpoint found: start the inclusive range
        inRange := True;
        InternalSetSelected(n, True);
        if AAnchor = ATarget then Break;  // degenerate: single-node range
      end
      else
      begin
        // Second endpoint: include it and we're done
        InternalSetSelected(n, True);
        Break;
      end;
    end
    else if inRange then
      InternalSetSelected(n, True);
    n := GetNextVisibleNoInit(n);
  end;
end;

function TTyTreeView.SelectedCount: Integer;
begin
  Result := FSelectionCount;
end;

{ ── D1 ── multi-select public API ────────────────────────────────────────── }

{ SelectAll — select all visible initialised nodes; update FSelectionCount;
  fire OnSelectionChanged if anything changed. }
procedure TTyTreeView.SelectAll;
var
  n:      PTyTreeNode;
  didAny: Boolean;
begin
  didAny := False;
  n := GetFirstVisibleNoInit;
  while n <> nil do
  begin
    if not (nsSelected in n^.States) then
    begin
      Include(n^.States, nsSelected);
      Inc(FSelectionCount);
      if FSelectedNode = nil then FSelectedNode := n;
      didAny := True;
    end;
    n := GetNextVisibleNoInit(n);
  end;
  if didAny then
  begin
    Invalidate;
    if Assigned(FOnSelectionChanged) then FOnSelectionChanged(Self);
  end;
end;

{ GetFirstSelected — return the first visible node with nsSelected, or nil. }
function TTyTreeView.GetFirstSelected: PTyTreeNode;
var
  n: PTyTreeNode;
begin
  n := GetFirstVisibleNoInit;
  while n <> nil do
  begin
    if nsSelected in n^.States then Exit(n);
    n := GetNextVisibleNoInit(n);
  end;
  Result := nil;
end;

{ GetNextSelected — return the next visible node after Node with nsSelected, or nil. }
function TTyTreeView.GetNextSelected(Node: PTyTreeNode): PTyTreeNode;
var
  n: PTyTreeNode;
begin
  if Node = nil then Exit(nil);
  n := GetNextVisibleNoInit(Node);
  while n <> nil do
  begin
    if nsSelected in n^.States then Exit(n);
    n := GetNextVisibleNoInit(n);
  end;
  Result := nil;
end;

function TTyTreeView.GetFocusedNode: PTyTreeNode;
begin
  Result := FFocusedNode;
end;

{ SetFocusedNode — moving focus also selects (single-select ③a rule):
  set focused node, select it, fire OnFocusChanged.
  Selecting also fires OnChange via SetSelected. }
procedure TTyTreeView.SetFocusedNode(AValue: PTyTreeNode);
var
  prevFocus: PTyTreeNode;
begin
  if AValue = FFocusedNode then Exit;
  prevFocus   := FFocusedNode;
  FFocusedNode := AValue;
  // Focusing selects in single-select mode.
  if AValue <> nil then
    SetSelected(AValue, True);
  if Assigned(FOnFocusChanged) then
    FOnFocusChanged(Self, AValue);
  Invalidate;
  { suppress unused-variable warning }
  if prevFocus = nil then ;
end;

{ MoveFocusOnly — move keyboard focus without touching the selection set.
  Used by the multi-select mouse/keyboard paths to position the caret
  independently of selection. }
procedure TTyTreeView.MoveFocusOnly(AValue: PTyTreeNode);
begin
  if AValue = FFocusedNode then Exit;
  FFocusedNode := AValue;
  if Assigned(FOnFocusChanged) then FOnFocusChanged(Self, AValue);
  Invalidate;
end;

{ AddRangeToSelection — Ctrl+Shift additive extend: add every visible node
  from AAnchor to ATarget (inclusive, order-independent) to the EXISTING
  selection without clearing.  InternalSetSelected ignores already-selected nodes. }
procedure TTyTreeView.AddRangeToSelection(AAnchor, ATarget: PTyTreeNode);
var
  n:       PTyTreeNode;
  inRange: Boolean;
begin
  if (AAnchor = nil) or (ATarget = nil) then Exit;
  inRange := False;
  n := GetFirstVisibleNoInit;
  while n <> nil do
  begin
    if (n = AAnchor) or (n = ATarget) then
    begin
      if not inRange then
      begin
        inRange := True;
        InternalSetSelected(n, True);
        if AAnchor = ATarget then Break;  // single-node degenerate
      end
      else
      begin
        InternalSetSelected(n, True);
        Break;
      end;
    end
    else if inRange then
      InternalSetSelected(n, True);
    n := GetNextVisibleNoInit(n);
  end;
end;

{ ── ③d C1 ── incremental type-to-find search ──────────────────────────────── }

{ GetNodeSearchText — the node's MAIN-column text, obtained exactly the way the
  caption is (OnGetTextWithType for the main column / ttNormal, falling back to
  OnGetText) so the search matches what the user actually sees. No side effects
  (never inits the node). }
function TTyTreeView.GetNodeSearchText(Node: PTyTreeNode): string;
begin
  Result := '';
  if (Node = nil) or (Node = FRoot) then Exit;
  if Assigned(FOnGetTextWithType) then
    FOnGetTextWithType(Self, Node, FHeader.MainColumn, ttNormal, Result)
  else if Assigned(FOnGetText) then
    FOnGetText(Self, Node, Result);
end;

{ NodeMatchesSearch — the match predicate for one candidate node.
  Default (OnIncrementalSearch unassigned) = case-insensitive PREFIX test of
  ASearchText against the node's main-column text (both upper-cased via
  UTF8UpperCase so multibyte casing is correct). When OnIncrementalSearch is
  assigned the app fully decides (AMatch seeded False). }
function TTyTreeView.NodeMatchesSearch(Node: PTyTreeNode; const ASearchText: string): Boolean;
var
  nodeText, upSearch: string;
begin
  Result := False;
  if (Node = nil) or (Node = FRoot) or (ASearchText = '') then Exit;
  if Assigned(FOnIncrementalSearch) then
  begin
    FOnIncrementalSearch(Self, Node, ASearchText, Result);
    Exit;
  end;
  { Default: case-insensitive prefix match on the main-column caption. }
  nodeText := UTF8UpperCase(GetNodeSearchText(Node));
  upSearch := UTF8UpperCase(ASearchText);
  Result := (upSearch <> '')
            and (UTF8Length(nodeText) >= UTF8Length(upSearch))
            and (UTF8Copy(nodeText, 1, UTF8Length(upSearch)) = upSearch);
end;

{ DoIncrementalSearch — walk the VISIBLE nodes (wrapping through the whole visible
  set) and move focus to the first node whose match predicate is True.

  Start position (mirrors Windows Explorer / VTV type-ahead):
   • A SINGLE-char buffer (a fresh search, or re-pressing the same letter) starts
     the walk AFTER the current focus, so repeats advance to the next match.
   • A MULTI-char buffer (the user is refining, e.g. 'b' then 'a') starts the walk
     AT the current focus (inclusive), so the focus stays put if it still matches
     the longer prefix instead of jumping to a later sibling.

  Lazy limitation: only visible (expanded-reachable) nodes are walked via
  GetNextVisibleNoInit — collapsed subtrees are never force-initialised, so a
  match hidden under a collapsed parent is not found (unlike VTV's isAll). }
procedure TTyTreeView.DoIncrementalSearch;
var
  start, n: PTyTreeNode;
  inclusive: Boolean;
begin
  if FSearchBuffer = '' then Exit;

  inclusive := UTF8Length(FSearchBuffer) > 1;   // refining → keep focus if it still matches

  if FFocusedNode <> nil then
  begin
    if inclusive then start := FFocusedNode
    else              start := GetNextVisibleNoInit(FFocusedNode);
  end
  else
    start := GetFirstVisibleNoInit;
  if start = nil then
    start := GetFirstVisibleNoInit;   // wrap to the top when focus was at the end

  n := start;
  while n <> nil do
  begin
    if NodeMatchesSearch(n, FSearchBuffer) then
    begin
      FocusedNode := n;     // selects (single-select rule) + fires OnFocusChanged
      ScrollIntoView(n);    // SetFocusedNode does not scroll on its own
      Exit;
    end;
    n := GetNextVisibleNoInit(n);
    if n = nil then
      n := GetFirstVisibleNoInit;   // wrap once through the whole visible set
    if n = start then Break;        // came full circle — no match
  end;
end;

{ ── C1 ── ToggleCheck — check-state toggle + events + radio + tri-state ─────── }

{ ToggleCheck — apply a user-driven check toggle to Node.
  Guards: Node<>nil, Node<>FRoot, toCheckSupport in FOptions, CheckType<>ctNone.
  Fires OnChecking (veto possible), toggles the state, propagates down/up when
  toAutoTristateTracking is in FOptions, fires OnChecked, repaints. }
procedure TTyTreeView.ToggleCheck(Node: PTyTreeNode);
var
  Allowed:  Boolean;
  sib:      PTyTreeNode;
  anc:      PTyTreeNode;
  newState: TTyCheckState;
begin
  { ── guards ── }
  if Node = nil then Exit;
  if Node = FRoot then Exit;
  if not (toCheckSupport in FOptions) then Exit;
  if Node^.CheckType = ctNone then Exit;

  { ── OnChecking veto ── }
  Allowed := True;
  if Assigned(FOnChecking) then FOnChecking(Self, Node, Allowed);
  if not Allowed then Exit;

  { ── apply by CheckType ── }
  case Node^.CheckType of

    ctCheckBox:
    begin
      { simple toggle: unchecked↔checked }
      if Node^.CheckState = csChecked then
        Node^.CheckState := csUnchecked
      else
        Node^.CheckState := csChecked;
    end;

    ctTriStateCheckBox:
    begin
      { user-click cycle: unchecked→checked→unchecked
        csMixed (set only by propagation) → user click goes to csChecked }
      case Node^.CheckState of
        csUnchecked: Node^.CheckState := csChecked;
        csChecked:   Node^.CheckState := csUnchecked;
        csMixed:     Node^.CheckState := csChecked;
      end;
    end;

    ctRadioButton:
    begin
      { radio: set this node csChecked; uncheck every ctRadioButton sibling }
      Node^.CheckState := csChecked;
      { walk the siblings (same Parent) }
      sib := Node^.Parent^.FirstChild;
      while sib <> nil do
      begin
        if (sib <> Node) and (sib^.CheckType = ctRadioButton) then
          sib^.CheckState := csUnchecked;
        sib := sib^.NextSibling;
      end;
      { radio nodes have no tri-state tracking; skip propagation below }
    end;

  end; { case }

  { ── toAutoTristateTracking ── }
  if toAutoTristateTracking in FOptions then
  begin
    if Node^.CheckType in [ctCheckBox, ctTriStateCheckBox] then
    begin
      { DOWN: push the new state to all already-initialised descendants }
      PropagateCheckDown(Node, Node^.CheckState);

      { UP: walk ancestors toward FRoot; recompute each and stop early when
        the state did not actually change (avoids pointless upward sweeps). }
      anc := Node^.Parent;
      while (anc <> nil) and (anc <> FRoot) do
      begin
        if anc^.CheckType in [ctCheckBox, ctTriStateCheckBox] then
        begin
          newState := RecomputeParentCheckState(anc);
          if anc^.CheckState = newState then Break;  { no change — stop }
          anc^.CheckState := newState;
        end;
        anc := anc^.Parent;
      end;
    end;
  end;

  { ── OnChecked + repaint ── }
  if Assigned(FOnChecked) then FOnChecked(Self, Node);
  Invalidate;
end;

{ ── C1 ── display property setters ─────────────────────────────────────────── }

procedure TTyTreeView.SetIndent(AValue: Integer);
begin
  if FIndent = AValue then Exit;
  FIndent := AValue;
  Invalidate;
end;

procedure TTyTreeView.SetImages(AValue: TImageList);
begin
  if FImages = AValue then Exit;
  FImages := AValue;
  Invalidate;
end;

procedure TTyTreeView.SetShowButtons(AValue: Boolean);
begin
  if FShowButtons = AValue then Exit;
  FShowButtons := AValue;
  Invalidate;
end;

procedure TTyTreeView.SetShowTreeLines(AValue: Boolean);
begin
  if FShowTreeLines = AValue then Exit;
  FShowTreeLines := AValue;
  Invalidate;
end;

procedure TTyTreeView.SetShowRoot(AValue: Boolean);
begin
  if FShowRoot = AValue then Exit;
  FShowRoot := AValue;
  Invalidate;
end;

procedure TTyTreeView.SetToggleOnDblClick(AValue: Boolean);
begin
  if FToggleOnDblClick = AValue then Exit;
  FToggleOnDblClick := AValue;
  Invalidate;
end;

procedure TTyTreeView.SetHotTrack(AValue: Boolean);
begin
  if FHotTrack = AValue then Exit;
  FHotTrack := AValue;
  Invalidate;
end;

{ ── B1 ── Options set + check array properties ──────────────────────────────── }

procedure TTyTreeView.SetOptions(AValue: TTyTreeOptions);
var
  CheckSupportChanged:  Boolean;
  MultiSelectRemoved:   Boolean;
  n:                    PTyTreeNode;
begin
  if FOptions = AValue then Exit;
  { ③e E4: toEditable being turned off mid-edit ⇒ COMMIT the open editor (matches
    the focus-loss semantics) before the option goes away. EndEditNode is a no-op
    when not editing, so non-editing trees are unaffected. }
  if FEditing and not (toEditable in AValue) then EndEditNode;
  CheckSupportChanged := (toCheckSupport in AValue) <> (toCheckSupport in FOptions);
  { FIX 5: detect toMultiSelect being removed while multiple nodes are selected }
  MultiSelectRemoved  := (toMultiSelect in FOptions) and
                         not (toMultiSelect in AValue) and
                         (FSelectionCount > 1);
  FOptions := AValue;
  if CheckSupportChanged then
  begin
    { Re-measure FRangeX when toCheckSupport toggles in multi-column mode,
      because the checkbox slot shifts the caption/image start in the main column. }
    if (FHeader <> nil) and (FHeader.Columns.Count > 0) then
      InvalidateTreeLayout;
  end;
  if MultiSelectRemoved then
  begin
    { Collapse to a single selection: keep FSelectedNode (or FocusedNode as
      fallback), clear nsSelected on all other nodes via the full structural walk,
      then restore the single selection. }
    if FSelectedNode = nil then FSelectedNode := FFocusedNode;
    ClearAllSelectedFull(FRoot);
    FSelectionCount := 0;
    FRangeAnchor    := nil;
    if FSelectedNode <> nil then
    begin
      Include(FSelectedNode^.States, nsSelected);
      FSelectionCount := 1;
    end;
    { Deselect any node that is still in FFocusedNode but not FSelectedNode }
    if (FFocusedNode <> nil) and (FFocusedNode <> FSelectedNode) then
    begin
      n := FFocusedNode;
      { keep FFocusedNode pointing to the surviving selection }
      FFocusedNode := FSelectedNode;
      if Assigned(FOnFocusChanged) then FOnFocusChanged(Self, n);
    end;
  end;
  Invalidate;
end;

function TTyTreeView.GetCheckType(Node: PTyTreeNode): TTyCheckType;
begin
  if Node = nil then Exit(ctNone);
  Result := Node^.CheckType;
end;

procedure TTyTreeView.SetCheckType(Node: PTyTreeNode; AValue: TTyCheckType);
begin
  if Node = nil then Exit;
  if Node^.CheckType = AValue then Exit;
  Node^.CheckType := AValue;
  Invalidate;
end;

function TTyTreeView.GetCheckState(Node: PTyTreeNode): TTyCheckState;
begin
  if Node = nil then Exit(csUnchecked);
  Result := Node^.CheckState;
end;

procedure TTyTreeView.SetCheckState(Node: PTyTreeNode; AValue: TTyCheckState);
begin
  if Node = nil then Exit;
  if Node^.CheckState = AValue then Exit;
  Node^.CheckState := AValue;
  Invalidate;
end;

function TTyTreeView.GetChecked(Node: PTyTreeNode): Boolean;
begin
  if Node = nil then Exit(False);
  Result := Node^.CheckState = csChecked;
end;

procedure TTyTreeView.SetChecked(Node: PTyTreeNode; AValue: Boolean);
begin
  if Node = nil then Exit;
  if AValue then
    SetCheckState(Node, csChecked)
  else
    SetCheckState(Node, csUnchecked);
end;

{ ── C1 ── bulk operations ───────────────────────────────────────────────────── }

{ FullExpandSubtree — recursive helper: init Node (so nsHasChildren is known),
  expand it if it has children (materialising them via InitChildren), then
  recurse into every materialised child.
  IMPORTANT: InitNode is called first so a fresh lazy tree (where nodes have
  not yet been visited) materialises correctly — without this, nsHasChildren
  would never be set and SetExpanded would silently do nothing. }
procedure FullExpandSubtree(Tree: TTyTreeView; Node: PTyTreeNode);
var
  child: PTyTreeNode;
begin
  if Node = nil then Exit;
  Tree.InitNode(Node);              // ensure nsHasChildren is determined
  if nsHasChildren in Node^.States then
    Tree.SetExpanded(Node, True);   // materialises children via InitChildren
  // Recurse into (now-materialised) children
  child := Node^.FirstChild;
  while child <> nil do
  begin
    FullExpandSubtree(Tree, child);
    child := child^.NextSibling;
  end;
end;

procedure TTyTreeView.FullExpand(Node: PTyTreeNode);
var
  child: PTyTreeNode;
begin
  if Node <> nil then
    FullExpandSubtree(Self, Node)
  else
  begin
    // Expand all top-level nodes and their descendants
    child := FRoot^.FirstChild;
    while child <> nil do
    begin
      FullExpandSubtree(Self, child);
      child := child^.NextSibling;
    end;
  end;
end;

{ FullCollapseSubtree — recursive helper: collapse Node then recurse into children. }
procedure FullCollapseSubtree(Tree: TTyTreeView; Node: PTyTreeNode);
var
  child: PTyTreeNode;
begin
  if Node = nil then Exit;
  // Recurse into children first (collapse leaves before parents)
  child := Node^.FirstChild;
  while child <> nil do
  begin
    FullCollapseSubtree(Tree, child);
    child := child^.NextSibling;
  end;
  if nsExpanded in Node^.States then
    Tree.SetExpanded(Node, False);
end;

procedure TTyTreeView.FullCollapse(Node: PTyTreeNode);
var
  child: PTyTreeNode;
begin
  if Node <> nil then
    FullCollapseSubtree(Self, Node)
  else
  begin
    child := FRoot^.FirstChild;
    while child <> nil do
    begin
      FullCollapseSubtree(Self, child);
      child := child^.NextSibling;
    end;
  end;
end;

{ ScrollIntoView — compute the node's absolute top by walking the visible
  sequence (no window handle needed), then clamp FOffsetY so the node is
  within the viewport.  Full scrollbar sync is Task C2.

  Clamp rules (FOffsetY ≤ 0, all in LOGICAL units):
    • If node is above the current viewport: FOffsetY := -nodeTop (scroll up).
    • If node is below: FOffsetY := -(nodeTop + NodeHeight - viewH) (scroll down).
    • FOffsetY is clamped to [-(FRangeY - viewH), 0].
      viewH = MulDiv(ClientHeight, 96, PPI) — the logical viewport height.
      When viewH ≥ FRangeY the clamp collapses to 0 (no scroll needed). }
procedure TTyTreeView.ScrollIntoView(Node: PTyTreeNode);
var
  n:       PTyTreeNode;
  accTop:  Integer;
  viewTop: Integer;      // viewport top in absolute coords = -FOffsetY (logical)
  viewBot: Integer;      // viewport bottom in absolute coords (logical)
  viewH:   Integer;      // logical viewport height
  nodeTop: Integer;
  minOff:  Integer;
begin
  if (Node = nil) or (Node = FRoot) then Exit;

  // Compute the node's absolute top via a visible-order walk.
  // All units here are LOGICAL (node heights are unscaled logical values).
  accTop := 0;
  n := GetFirstVisibleNoInit;
  nodeTop := -1;
  while n <> nil do
  begin
    if n = Node then
    begin
      nodeTop := accTop;
      Break;
    end;
    Inc(accTop, n^.NodeHeight);
    n := GetNextVisibleNoInit(n);
  end;
  if nodeTop < 0 then Exit;   // node is not visible in the current tree

  // ClientHeight is device pixels; convert to logical so all comparisons are
  // consistent with the logical FOffsetY / FRangeY / NodeHeight units.
  viewH   := MulDiv(ClientHeight, 96, Font.PixelsPerInch);
  viewTop := -FOffsetY;
  viewBot := viewTop + viewH;

  if nodeTop < viewTop then
  begin
    // Node is above the viewport — scroll up so node is at the top.
    FOffsetY := -nodeTop;
  end
  else if nodeTop + Integer(Node^.NodeHeight) > viewBot then
  begin
    // Node is below the viewport — scroll down so the bottom of the node is at the bottom.
    FOffsetY := -(nodeTop + Integer(Node^.NodeHeight) - viewH);
  end
  else
    Exit;   // already in view — nothing to do

  // Clamp FOffsetY to [-(FRangeY - viewH), 0]
  minOff := viewH - FRangeY;
  if minOff > 0 then minOff := 0;   // when content shorter than viewport: no negative offset needed
  if FOffsetY < minOff then FOffsetY := minOff;
  if FOffsetY > 0 then FOffsetY := 0;

  UpdateScrollBars;   // sync the scrollbar thumb to the new offset
  Invalidate;
  RepositionEditor;   // ③e E4: keep an open editor glued to its cell after scroll
end;

{ ── C2 ── embedded scrollbars + offsets ─────────────────────────────────── }

{ ContentHeight: the scrollable pixel height of the visible node sequence.
  The hidden root's own NodeHeight is NOT part of the scroll space — it is a
  phantom sentinel row that never appears on screen.  So:
    ContentHeight = RootNode^.TotalHeight - RootNode^.NodeHeight
  This is the value used for FRangeY and for scrollbar Max. }
function TTyTreeView.ContentHeight: Integer;
begin
  Result := Integer(FRoot^.TotalHeight) - Integer(FRoot^.NodeHeight);
end;

{ ContentRect: the sub-rectangle of ClientRect available for tree content.
  Insets for the themed padding (matching RenderTo's CR exactly) and shrinks
  the right/bottom edges when the respective scrollbar is visible.
  With no controller the padding is 0, so the result equals the old ClientRect
  minus scrollbar thickness — headless tests that use Create(nil) are unaffected. }
function TTyTreeView.ContentRect: TRect;
var
  SBThick, PPI: Integer;
  S: TTyStyleSet;
  CR: TRect;
begin
  S   := CurrentStyle;
  PPI := Font.PixelsPerInch;
  CR  := ClientRect;
  Result := Rect(
    CR.Left   + MulDiv(S.Padding.Left,   PPI, 96),
    CR.Top    + MulDiv(S.Padding.Top,    PPI, 96),
    CR.Right  - MulDiv(S.Padding.Right,  PPI, 96),
    CR.Bottom - MulDiv(S.Padding.Bottom, PPI, 96));
  SBThick := MulDiv(TyScrollbarSize, PPI, 96);
  if (FVScroll <> nil) and FVScroll.Visible then
    Dec(Result.Right,  SBThick);
  if (FHScroll <> nil) and FHScroll.Visible then
    Dec(Result.Bottom, SBThick);
  { B (columns): when hoVisible AND there are columns, inset Top by the header height.
    Guard: Columns.Count = 0 → ③a path unchanged (no inset). }
  if (FHeader <> nil) and (FHeader.Columns.Count > 0) and
     (hoVisible in FHeader.Options) then
    Inc(Result.Top, MulDiv(FHeader.Height, PPI, 96));
end;

{ UpdateScrollBars: show/hide and configure each scrollbar based on the
  current content size vs viewport size.  Mirrors ListBox.UpdateScrollBar.

  Vertical bar:
    Visible iff ContentHeight > viewport height.
    Max      = ContentHeight
    PageSize = viewport height
    Position = -FOffsetY (FOffsetY ≤ 0)

  Horizontal bar:
    Visible iff FRangeX > viewport width.
    FRangeX is reset to 0 by InvalidateTreeLayout on every structural change
    and then re-accumulated during the paint pass (C3).  So between a structural
    change and the next repaint the bar is correctly hidden, and after the repaint
    it reflects the true widest visible row.

  FOffsetY is clamped to [-(ContentHeight - viewportH), 0] each call. }
procedure TTyTreeView.UpdateScrollBars;
var
  SBThick, viewW, viewH, contH, PPI: Integer;
  wantVScroll, wantHScroll: Boolean;
begin
  PPI     := Font.PixelsPerInch;
  SBThick := MulDiv(TyScrollbarSize, PPI, 96);

  { Vertical model: logical units, so they agree with the logical node heights
    stored in ContentHeight / FOffsetY / FRangeY.
    ClientHeight is device pixels; convert to logical via MulDiv(…,96,PPI).
    At 96 DPI MulDiv(n,96,96)=n, so headless tests (PPI=96) are unaffected.
    Horizontal model: device pixels (FRangeX/FOffsetX are device-pixel
    quantities accumulated by RenderTo via P.Scale — the X axis is already
    correct and must remain device throughout). }
  viewH := MulDiv(ClientHeight, 96, PPI);   // logical viewport height
  viewW := ClientWidth;                      // device viewport width (X axis)
  contH := ContentHeight;

  { Decide which bars are needed.  The presence of a vertical bar steals width
    from the horizontal viewport (device), and the presence of a horizontal bar
    steals height from the vertical viewport (logical).  SBThick is device;
    convert it to logical when adjusting viewH. }
  wantVScroll := contH > viewH;
  if wantVScroll then viewW := viewW - SBThick;
  wantHScroll := FRangeX > viewW;
  if wantHScroll then viewH := viewH - MulDiv(SBThick, 96, PPI);
  if (not wantVScroll) and (contH > viewH) then
  begin
    wantVScroll := True;
    viewW := ClientWidth - SBThick;
  end;

  { ── Vertical bar ────────────────────────────────────────────────────────── }
  if wantVScroll then
  begin
    { Bars always exist (created in constructor); just configure and show. }
    FVScroll.Width      := SBThick;
    FVScroll.Controller := Self.Controller;
    { Position the bar along the right edge (above any horizontal bar). }
    if not FVScroll.Dragging then
    begin
      if wantHScroll then
        FVScroll.SetBounds(Width - SBThick, 0, SBThick, Height - SBThick)
      else
        FVScroll.SetBounds(Width - SBThick, 0, SBThick, Height);
    end;

    { Clamp FOffsetY to [-(contentH - viewH), 0] before syncing the thumb. }
    if contH > viewH then
    begin
      if FOffsetY < -(contH - viewH) then FOffsetY := -(contH - viewH);
    end
    else
      FOffsetY := 0;   // content fits in the viewport
    if FOffsetY > 0 then FOffsetY := 0;

    if not FVScroll.Dragging then
    begin
      FSyncingScroll := True;
      try
        FVScroll.Min      := 0;
        FVScroll.Max      := contH;
        FVScroll.PageSize := viewH;
        FVScroll.Position := -FOffsetY;
      finally
        FSyncingScroll := False;
      end;
    end;
    FVScroll.Visible := True;
  end
  else
  begin
    FVScroll.Visible := False;
    FOffsetY := 0;
  end;

  { ── Horizontal bar ─────────────────────────────────────────────────────── }
  if wantHScroll then
  begin
    FHScroll.Height     := SBThick;
    FHScroll.Controller := Self.Controller;
    { Position the bar along the bottom edge (left of the vertical bar). }
    if not FHScroll.Dragging then
    begin
      if wantVScroll then
        FHScroll.SetBounds(0, Height - SBThick, Width - SBThick, SBThick)
      else
        FHScroll.SetBounds(0, Height - SBThick, Width, SBThick);
    end;

    if FOffsetX < -(FRangeX - viewW) then FOffsetX := -(FRangeX - viewW);
    if FOffsetX > 0 then FOffsetX := 0;

    if not FHScroll.Dragging then
    begin
      FSyncingScroll := True;
      try
        FHScroll.Min      := 0;
        FHScroll.Max      := FRangeX;
        FHScroll.PageSize := viewW;
        FHScroll.Position := -FOffsetX;
      finally
        FSyncingScroll := False;
      end;
    end;
    FHScroll.Visible := True;
  end
  else
  begin
    FHScroll.Visible := False;
    FOffsetX := 0;
  end;
end;

{ VScrollChange — fired by the vertical scrollbar when the user drags/clicks it.
  Convert Position (0..Max) back to FOffsetY (≤ 0). }
procedure TTyTreeView.VScrollChange(Sender: TObject);
begin
  if FSyncingScroll then Exit;
  FSyncingScroll := True;
  try
    FOffsetY := -FVScroll.Position;
    Invalidate;
  finally
    FSyncingScroll := False;
  end;
  RepositionEditor;   // ③e E4: keep an open editor glued to its cell after scroll
end;

{ HScrollChange — horizontal bar counterpart. }
procedure TTyTreeView.HScrollChange(Sender: TObject);
begin
  if FSyncingScroll then Exit;
  FSyncingScroll := True;
  try
    FOffsetX := -FHScroll.Position;
    Invalidate;
  finally
    FSyncingScroll := False;
  end;
  RepositionEditor;   // ③e E4: keep an open editor glued to its cell after scroll
end;

{ DoMouseWheel — scroll 3 rows per detent (mirrors ListBox wheel).
  WheelDelta > 0 = scroll up (content moves down, FOffsetY increases toward 0);
  WheelDelta < 0 = scroll down (FOffsetY decreases). }
function TTyTreeView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
var
  Delta, step: Integer;
begin
  if not Enabled then Exit(False);
  if inherited DoMouseWheel(Shift, WheelDelta, MousePos) then Exit(True);

  // ③d B1: page/wheel estimates use FDefaultNodeHeight even under
  // toVariableNodeHeight — an acceptable approximation (no per-node walk here).
  step := 3 * FDefaultNodeHeight;
  if WheelDelta > 0 then Delta :=  step   // scroll up
  else                    Delta := -step;  // scroll down

  FOffsetY := FOffsetY + Delta;
  UpdateScrollBars;   // clamps FOffsetY and syncs thumb
  Invalidate;
  RepositionEditor;   // ③e E4: keep an open editor glued to its cell after wheel scroll
  Result := True;
end;

{ Resize — recalculate scrollbar visibility/geometry on layout change.
  D4: when hoAutoResize is on, re-apply auto-size so the designated column fills
  the remaining width whenever the control is resized. }
procedure TTyTreeView.Resize;
var
  PPI, contentW: Integer;
begin
  inherited Resize;
  UpdateScrollBars;
  { D4: auto-size hook — runs after UpdateScrollBars so ContentRect is current }
  if (FHeader <> nil) and (hoAutoResize in FHeader.Options) and
     (FHeader.AutoSizeIndex >= 0) and
     (FHeader.AutoSizeIndex < FHeader.Columns.Count) and
     (FHeader.Columns.Count > 0) then
  begin
    PPI      := Font.PixelsPerInch;
    contentW := MulDiv(ContentRect.Width, 96, PPI);
    FHeader.Columns.ApplyAutoSize(contentW, FHeader.AutoSizeIndex);
    if FHeader.Columns.Count > 0 then
      FRangeX := MulDiv(FHeader.Columns.TotalWidth, Font.PixelsPerInch, 96);
    UpdateScrollBars;
  end;
  RepositionEditor;   // ③e E4: keep an open editor glued to its cell after a resize
end;

{ B (columns): header/column change handler }
procedure TTyTreeView.HeaderChanged(Sender: TObject);
begin
  { Guard: skip during destruction (FRoot is nil after Clear+FreeNodeMem). }
  if FRoot = nil then Exit;
  { Recompute the horizontal range from column total width (when columns exist),
    invalidate the layout cache, and request a repaint.
    When Columns.Count = 0 FRangeX stays 0 — the ③a paint pass accumulates it. }
  if (FHeader <> nil) and (FHeader.Columns.Count > 0) then
    FRangeX := MulDiv(FHeader.Columns.TotalWidth, Font.PixelsPerInch, 96)
  else
    FRangeX := 0;
  InvalidateTreeLayout;
  { E2/E3: when the sort key changes programmatically (not via _HandleHeaderClick),
    and auto-sort is active, re-sort the tree.  The FSorting guard prevents
    _HandleHeaderClick → SortColumn setter → HeaderChanged → SortTree infinite loop. }
  if (not FSorting) and (FHeader <> nil) and
     (hoHeaderClickAutoSort in FHeader.Options) and
     (FHeader.SortColumn >= 0) and
     ((FHeader.SortColumn <> FSortedColumn) or
      (FHeader.SortDirection <> FSortedDirection)) then
    SortTree(FHeader.SortColumn, FHeader.SortDirection);
  Invalidate;
end;

procedure TTyTreeView.SetHeader(AValue: TTyTreeHeader);
begin
  FHeader.Assign(AValue);
end;

constructor TTyTreeView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FNodeDataSize := -1;
  FNodeAllocSize := TreeNodeSize;
  FDefaultNodeHeight := 18;
  FRoot := MakeNewNode;                  // hidden root
  FRoot^.Parent := PTyTreeNode(Self);    // sentinel — root's Parent points back at the tree
  FRoot^.PrevSibling := FRoot;
  FRoot^.NextSibling := FRoot;
  // Root is always "expanded" so its children contribute height
  Include(FRoot^.States, nsExpanded);
  { C1 defaults }
  FIndent           := 16;
  FShowButtons      := True;
  FShowTreeLines    := True;
  FShowRoot         := True;
  FToggleOnDblClick := True;
  FHotTrack         := False;
  { C2 scroll state — both scrollbars are created here in the constructor so
    they always have proper window handles and receive mouse events.  Creating
    them lazily inside UpdateScrollBars (which is called from RenderTo) meant
    they were first created during a WM_PAINT, which left them without a valid
    HWND parent-chain → they painted but never received MouseDown → undraggable. }
  FOffsetY       := 0;
  FOffsetX       := 0;
  FRangeX        := 0;
  FSyncingScroll := False;
  { D2: column resize — idle state }
  FResizeColumn     := NoColumn;
  FResizeStartWidth := 0;
  FResizeStartX     := 0;
  { D3: column drag-reorder — idle state }
  FDragColumn       := NoColumn;
  FDragPending      := False;
  FDragStartX       := 0;
  FDragging         := False;
  FDragTargetPos    := 0;
  { E1/E2/E3: sort engine — idle state }
  FSorting          := False;
  FSortedColumn     := NoColumn;   // no key sorted yet (so the first real sort runs)
  FSortedDirection  := sdAscending;
  { ③d C1: incremental search — idle state }
  FSearchBuffer     := '';
  FSearchLastTick   := 0;
  FSearchTimeout    := 1000;
  FEditing          := False;
  { ③e E1: inline-edit — idle state }
  FEditNode         := nil;
  FEditColumn       := NoColumn;
  FEditOriginalText := '';
  FEndingEdit       := False;
  FLastMouseColumn  := NoColumn;
  FLastMouseHitPart := hpNowhere;
  FVScroll := TTyScrollBar.Create(Self);
  FVScroll.Parent            := Self;
  FVScroll.Kind              := sbVertical;
  FVScroll.AnimationsEnabled := False;
  FVScroll.OnChange          := @VScrollChange;
  FVScroll.Visible           := False;
  FHScroll := TTyScrollBar.Create(Self);
  FHScroll.Parent            := Self;
  FHScroll.Kind              := sbHorizontal;
  FHScroll.AnimationsEnabled := False;
  FHScroll.OnChange          := @HScrollChange;
  FHScroll.Visible           := False;
  { B (columns): create the header sub-object and wire its change notification }
  FHeader := TTyTreeHeader.Create;
  FHeader.OnChange := @HeaderChanged;
  { ③e E1: the persistent inline editor — hidden, non-tab-stop, parented to the
    tree so it shares the tree's Controller (themed automatically) and lives in
    the same client coordinate space the cell rects use. Shown + positioned on
    demand by EditNode (E2); dormant while toEditable is off. }
  FEditor := TTyEdit.Create(Self);
  FEditor.Parent  := Self;
  FEditor.Visible := False;
  FEditor.TabStop := False;
  { ③e E4: editor input — Enter commits, Esc cancels (EditorKeyDown), and losing
    focus commits Explorer-style (EditorExit). }
  FEditor.OnKeyDown := @EditorKeyDown;
  FEditor.OnExit    := @EditorExit;
  TabStop           := True;
  Width := 200; Height := 160;
end;

destructor TTyTreeView.Destroy;
begin
  // Null out selection/focus pointers before Clear so no dangling refs remain.
  FFocusedNode  := nil;
  FSelectedNode := nil;
  // Clear fires OnFreeNode for every node so managed fields in user data blobs
  // are properly released.  Do NOT nil FOnFreeNode before Clear — that would
  // silently skip the release path and leak any AnsiString/interface stored in
  // node data.  (The fire site already guards with Assigned(FOnFreeNode).)
  Clear;
  if FRoot <> nil then
  begin
    FreeNodeMem(FRoot);
    FRoot := nil;
  end;
  { B (columns): free the header sub-object }
  FHeader.Free;
  FHeader := nil;
  inherited Destroy;
end;

function TTyTreeView.MakeNewNode: PTyTreeNode;
begin
  Result := AllocMem(FNodeAllocSize);    // zero-filled by AllocMem
  Result^.States := [nsVisible];
  Result^.NodeHeight := FDefaultNodeHeight;
  // TotalCount and TotalHeight for a fresh leaf: count=1, height=NodeHeight
  Result^.TotalCount := 1;
  Result^.TotalHeight := FDefaultNodeHeight;
end;

procedure TTyTreeView.FreeNodeMem(Node: PTyTreeNode);
begin
  FreeMem(Node);
end;

procedure TTyTreeView.SetNodeDataSize(AValue: Integer);
begin
  if FNodeDataSize = AValue then Exit;
  // Must be set before any nodes exist (changes the allocation stride).
  FNodeDataSize := AValue;
  if AValue > 0 then FNodeAllocSize := TreeNodeSize + AValue
  else FNodeAllocSize := TreeNodeSize;
end;

function TTyTreeView.GetNodeData(Node: PTyTreeNode): Pointer;
begin
  if (FNodeDataSize <= 0) or (Node = nil) or (Node = FRoot) then
    Result := nil
  else
    Result := PByte(Node) + TreeNodeSize;
end;

procedure TTyTreeView.AdjustTotalCount(Node: PTyTreeNode; Delta: Integer);
var
  run: PTyTreeNode;
begin
  run := Node;
  while run <> nil do
  begin
    Inc(run^.TotalCount, Delta);
    run := run^.Parent;
    if run = PTyTreeNode(Self) then Break;  // reached the sentinel above root
  end;
end;

procedure TTyTreeView.AdjustTotalHeight(Node: PTyTreeNode; Delta: Integer);
{ Propagates a pixel delta up the ancestor chain.
  INVARIANT: a parent's TotalHeight includes a child's contribution ONLY when the
  PARENT is expanded.  Therefore, before adding Delta to a parent, we check whether
  the PARENT is expanded — not whether the child (run) is expanded.
  This is ordering-independent: the caller may set/clear nsExpanded on Node before
  or after calling AdjustTotalHeight and the result is still correct.
  (The old code checked run^.States BEFORE climbing, which wrongly inflated a
  collapsed ancestor when a deeply-nested node was expanded programmatically.) }
var
  run, up: PTyTreeNode;
begin
  if Delta = 0 then Exit;
  Inc(Node^.TotalHeight, Delta);          // the changed node's own total always reflects the delta
  run := Node;
  while True do
  begin
    up := run^.Parent;
    if (up = nil) or (up = PTyTreeNode(Self)) then Break;  // reached the root sentinel
    if not (nsExpanded in up^.States) then Break;  // parent collapsed: its total excludes run's subtree
    Inc(up^.TotalHeight, Delta);
    run := up;
  end;
end;

procedure TTyTreeView.InvalidateTreeLayout;
begin
  // B1: mark the position cache dirty and recompute FRangeY.
  // FRangeY = ContentHeight (the scrollable content height, root phantom row excluded).
  FCacheValid := False;
  FRangeY     := ContentHeight;
  // Reset FRangeX.  When columns exist, the horizontal range is TotalWidth
  // (driven by the column model, not by measured text).  When there are no
  // columns (③a path), reset to 0 so the next paint pass re-accumulates
  // the true maximum row width from scratch.
  if (FHeader <> nil) and (FHeader.Columns.Count > 0) then
    FRangeX := MulDiv(FHeader.Columns.TotalWidth, Font.PixelsPerInch, 96)
  else
    FRangeX := 0;
  UpdateScrollBars;
  Invalidate;
  { ③e E4: central layout hub — covers expand/collapse, per-node height change,
    column resize/reorder (via HeaderChanged) and structural growth. DeleteNode /
    Clear CancelEdit *before* they reach here, so FEditNode is already nulled and
    RepositionEditor safely no-ops (it never touches the freed node). }
  RepositionEditor;
end;

function TTyTreeView.SumVisibleHeights: Integer;
{ Walk all screen-order visible nodes and sum their NodeHeight values.
  Used ONLY by the B1 invariant test and debug assertions — not in the hot path. }
var
  n: PTyTreeNode;
begin
  Result := 0;
  n := GetFirstVisibleNoInit;
  while n <> nil do
  begin
    Inc(Result, n^.NodeHeight);
    n := GetNextVisibleNoInit(n);
  end;
  // Add the root's own NodeHeight (the root sentinel always counts itself)
  Inc(Result, FRoot^.NodeHeight);
end;

function TTyTreeView.GetRootNodeCount: Cardinal;
begin
  Result := FRoot^.ChildCount;
end;

procedure TTyTreeView.SetRootNodeCount(AValue: Cardinal);
begin
  SetChildCount(FRoot, AValue);
end;

procedure TTyTreeView.SetChildCount(Node: PTyTreeNode; NewCount: Cardinal);
var
  i: Cardinal;
  child, prev: PTyTreeNode;
  addedH, addedC: Integer;
begin
  if NewCount = Node^.ChildCount then Exit;
  if NewCount > Node^.ChildCount then
  begin
    addedH := 0; addedC := 0;
    prev := Node^.LastChild;
    for i := Node^.ChildCount to NewCount - 1 do
    begin
      child := MakeNewNode;
      child^.Parent := Node;
      child^.Index := i;
      child^.PrevSibling := prev;
      if prev <> nil then prev^.NextSibling := child
      else Node^.FirstChild := child;
      Node^.LastChild := child;
      prev := child;
      Inc(addedC);
      Inc(addedH, child^.NodeHeight);
    end;
    Node^.ChildCount := NewCount;
    // Each new node has TotalCount=1; increment ancestors by addedC
    AdjustTotalCount(Node, addedC);
    // Children contribute height only when parent is expanded (root is always expanded)
    if (nsExpanded in Node^.States) or (Node = FRoot) then
      AdjustTotalHeight(Node, addedH);
  end
  else
  begin
    // Shrink: delete tail children one by one (DeleteNode handles recursion + OnFreeNode).
    // Each DeleteNode call already fires InvalidateTreeLayout; no extra call needed here.
    while Node^.ChildCount > NewCount do
      DeleteNode(Node^.LastChild);
    Exit;  // skip the grow-path InvalidateTreeLayout below
  end;
  InvalidateTreeLayout;
end;

function TTyTreeView.AddChild(AParent: PTyTreeNode): PTyTreeNode;
var
  p: PTyTreeNode;
begin
  if AParent = nil then p := FRoot else p := AParent;
  SetChildCount(p, p^.ChildCount + 1);
  Result := p^.LastChild;
  // Mark the parent as having children if it isn't the root and wasn't already marked
  if (p <> FRoot) and not (nsHasChildren in p^.States) then
    Include(p^.States, nsHasChildren);
end;

procedure TTyTreeView.DeleteNode(Node: PTyTreeNode);
var
  nodeParent: PTyTreeNode;
  dh, dc:     Integer;
  reseqChild: PTyTreeNode;   { A1: for sibling re-sequence walk }
  reseqIdx:   Cardinal;
  anc:        PTyTreeNode;   { ③e E4: ancestor walk to detect the edited subtree }
begin
  if (Node = nil) or (Node = FRoot) then Exit;

  { ③e E4: if the active edit lives in the subtree about to be freed (the node
    itself or any descendant), CANCEL it (no commit on a vanishing node) BEFORE
    anything is freed. CancelEdit → FinishEdit nulls FEditNode, so the recursive
    child-frees + the trailing InvalidateTreeLayout → RepositionEditor see
    FEditing=False and never dereference the freed pointer. }
  if FEditing and (FEditNode <> nil) then
  begin
    anc := FEditNode;
    while anc <> nil do
    begin
      if anc = Node then begin CancelEdit; Break; end;
      anc := anc^.Parent;
      if anc = FRoot then Break;   { reached the sentinel root — not in this subtree }
    end;
  end;

  // Null out selection/focus/hover if this node (or an ancestor) is being deleted
  if FFocusedNode   = Node then FFocusedNode   := nil;
  if FLastMouseNode = Node then
  begin
    FLastMouseNode := nil;
    { FIX 6 (adversarial): the recorded mouse column/part referred to the now-gone
      node; reset them so a later edit trigger (DblClick/F2) can't act on a stale
      column from a freed node. }
    FLastMouseColumn  := NoColumn;
    FLastMouseHitPart := hpNowhere;
  end;
  if FHotNode       = Node then FHotNode       := nil;
  { FIX 1: selection bookkeeping — clear nsSelected + decrement count for THIS
    node BEFORE the recursive child-free loop below, so that every descendant
    also runs through DeleteNode and gets the same treatment.  We handle this
    node's own state here; children are handled recursively. }
  if nsSelected in Node^.States then
  begin
    Exclude(Node^.States, nsSelected);
    if FSelectionCount > 0 then Dec(FSelectionCount);
  end;
  if FSelectedNode = Node then FSelectedNode := nil;
  if FRangeAnchor  = Node then FRangeAnchor  := nil;

  // Recursively free all children first (depth-first)
  while Node^.FirstChild <> nil do DeleteNode(Node^.FirstChild);

  nodeParent := Node^.Parent;
  // dc = how many nodes we're removing from ancestor counts.
  // All children have already been freed above, so TotalCount is authoritatively 1 here.
  dc := Node^.TotalCount;  // = 1 after recursive child frees; avoids magic literal

  // Height delta: only subtract from ancestors when nodeParent contributes visible heights
  if (nsExpanded in nodeParent^.States) or (nodeParent = FRoot) then
    dh := Node^.NodeHeight   // node is a leaf now, its TotalHeight = NodeHeight
  else
    dh := 0;

  // Fire OnFreeNode so app can release managed fields in the data blob
  if Assigned(FOnFreeNode) then
    FOnFreeNode(Self, Node);

  // Unlink from siblings
  if Node^.PrevSibling <> nil then
    Node^.PrevSibling^.NextSibling := Node^.NextSibling
  else
    nodeParent^.FirstChild := Node^.NextSibling;

  if Node^.NextSibling <> nil then
    Node^.NextSibling^.PrevSibling := Node^.PrevSibling
  else
    nodeParent^.LastChild := Node^.PrevSibling;

  Dec(nodeParent^.ChildCount);

  // Adjust aggregate counts on the nodeParent chain
  AdjustTotalCount(nodeParent, -dc);
  if dh <> 0 then AdjustTotalHeight(nodeParent, -dh);

  // Clear nsHasChildren when the last child is removed
  if nodeParent^.ChildCount = 0 then
    Exclude(nodeParent^.States, nsHasChildren);

  { A1: re-sequence the remaining siblings' Index values (0-based, consecutive).
    Skipped during Clear (nsClearing on FRoot), so bulk teardown stays O(n).
    FIX 2: guard on FRoot^.States, not nodeParent^.States — nsClearing is set only
    on FRoot, so checking nodeParent caused O(k^2) re-sequences on intermediate
    nodes during Clear even though FRoot was already marked. }
  if not (nsClearing in FRoot^.States) then
  begin
    reseqChild := nodeParent^.FirstChild;
    reseqIdx   := 0;
    while reseqChild <> nil do
    begin
      reseqChild^.Index := reseqIdx;
      Inc(reseqIdx);
      reseqChild := reseqChild^.NextSibling;
    end;
  end;

  FreeNodeMem(Node);
  InvalidateTreeLayout;
end;

procedure TTyTreeView.Clear;
begin
  { ③e E4: any active edit is on a node about to be freed — CANCEL it (no commit)
    BEFORE the teardown so FEditNode can't dangle. (DeleteNode's own subtree check
    would also catch it per-node, but cancelling once up-front is cheaper + clearer
    for a bulk clear.) }
  if FEditing then CancelEdit;
  { A1: mark FRoot with nsClearing so DeleteNode skips the O(siblings) index
    re-sequence during bulk teardown, keeping Clear O(n). }
  Include(FRoot^.States, nsClearing);
  try
    while FRoot^.FirstChild <> nil do DeleteNode(FRoot^.FirstChild);
  finally
    Exclude(FRoot^.States, nsClearing);
  end;
  { FIX 1: make bookkeeping authoritative after teardown — DeleteNode decrements
    per-node, but Clear guarantees all nodes are gone so these must be 0/nil. }
  FSelectionCount := 0;
  FSelectedNode   := nil;
  FRangeAnchor    := nil;
  FEditNode       := nil;   { ③e E4: dangling-pointer hygiene (CancelEdit already nulled it) }
end;

{ ── A5 ── lazy lifecycle ─────────────────────────────────────────────────── }

{ ComputeExpandedSubtreeHeight
  Returns the total pixel height that Node and ALL its currently-expanded
  descendants would occupy if Node itself were visible.
  This is a pure recursive walk — called only when we NEED the exact value
  (on expand/collapse) and not in the hot paint path. }
function TTyTreeView.ComputeExpandedSubtreeHeight(Node: PTyTreeNode): Integer;
var
  child: PTyTreeNode;
begin
  if Node = nil then begin Result := 0; Exit; end;
  Result := Node^.NodeHeight;
  if (nsExpanded in Node^.States) and (Node^.FirstChild <> nil) then
  begin
    child := Node^.FirstChild;
    while child <> nil do
    begin
      Inc(Result, ComputeExpandedSubtreeHeight(child));
      child := child^.NextSibling;
    end;
  end;
end;

function TTyTreeView.GetExpanded(Node: PTyTreeNode): Boolean;
begin
  Result := (Node <> nil) and (nsExpanded in Node^.States);
end;

{ ③d B1: per-node row-height accessors. }
function TTyTreeView.GetNodeHeight(Node: PTyTreeNode): Integer;
begin
  if Node = nil then Result := FDefaultNodeHeight
  else Result := Node^.NodeHeight;
end;

procedure TTyTreeView.SetNodeHeight(Node: PTyTreeNode; AValue: Integer);
{ Programmatic per-node height override (mirrors VTV SetNodeHeight). Applies the
  delta up the ancestor chain via AdjustTotalHeight so the ③a invariant holds,
  marks the node measured (so a later InitNode measure won't clobber it), and
  invalidates the layout (cache rebuild + repaint). No-op when unchanged. }
begin
  if (Node = nil) or (Node = FRoot) then Exit;
  if AValue <= 0 then Exit;                              // guard: heights are positive
  Include(Node^.States, nsHeightMeasured);               // explicit set counts as measured
  if AValue = Integer(Node^.NodeHeight) then Exit;       // no-op if unchanged
  AdjustTotalHeight(Node, AValue - Integer(Node^.NodeHeight));
  Node^.NodeHeight := Word(AValue);
  InvalidateTreeLayout;
end;

procedure TTyTreeView.InitNode(Node: PTyTreeNode);
var
  initStates: TTyNodeInitStates;
  h: Integer;
begin
  if (Node = nil) or (Node = FRoot) or (nsInitialized in Node^.States) then Exit;
  Include(Node^.States, nsInitialized);
  initStates := [];
  if Assigned(FOnInitNode) then
    FOnInitNode(Self, Node^.Parent, Node, initStates);
  if ivsHasChildren in initStates then
    Include(Node^.States, nsHasChildren);
  if ivsSelected in initStates then
    SetSelected(Node, True);   // C1: full single-select semantics (fires OnChange)
  if ivsExpanded in initStates then
    SetExpanded(Node, True);             // materialise children if the app requests auto-expand

  { ③d B1: variable per-node row height. Measure ONCE, at the END of InitNode
    (never in GetNodeAt — re-entrant layout risk). The paint loop calls InitNode
    before reading NodeHeight, so the measure lands at the right time. The height
    is kept in the node field (persists), and AdjustTotalHeight keeps the ③a
    invariant (RootNode^.TotalHeight == Σ visible NodeHeight). When a height
    actually changes we mark the layout dirty so the position cache — built by
    GetNextVisibleNoInit (no init) and thus possibly cold/unmeasured — rebuilds
    with the measured values on the next access. }
  if (toVariableNodeHeight in FOptions) and Assigned(FOnMeasureItem)
     and not (nsHeightMeasured in Node^.States) then
  begin
    h := Node^.NodeHeight;                              // seed with current/default
    FOnMeasureItem(Self, Canvas, Node, h);
    if (h > 0) and (h <> Integer(Node^.NodeHeight)) then
    begin
      AdjustTotalHeight(Node, h - Integer(Node^.NodeHeight));  // keep the invariant
      Node^.NodeHeight := Word(h);
      InvalidateTreeLayout;   // force the position cache to rebuild with the measured height
    end;
    Include(Node^.States, nsHeightMeasured);
  end;
end;

procedure TTyTreeView.InitChildren(Node: PTyTreeNode);
var
  c: Cardinal;
begin
  if (Node = nil) or (Node = FRoot) then Exit;
  if Node^.ChildCount > 0 then Exit;           // already materialised
  if not (nsHasChildren in Node^.States) then Exit;
  c := 0;
  if Assigned(FOnInitChildren) then
    FOnInitChildren(Self, Node, c);
  if c > 0 then
    SetChildCount(Node, c)
  else
    Exclude(Node^.States, nsHasChildren);       // app says "actually no children"
end;

procedure TTyTreeView.SetExpanded(Node: PTyTreeNode; AValue: Boolean);
{ Height-bookkeeping invariant (asserted by B1):
    RootNode^.TotalHeight = sum of NodeHeight for every visible (nsVisible + reachable via
    nsExpanded ancestors) node.
  When a node is EXPANDED:
    • Its children are just-materialised collapsed skeletons; each child's TotalHeight = NodeHeight.
    • We add the delta = ComputeExpandedSubtreeHeight(Node) − current TotalHeight.
      (current TotalHeight equals NodeHeight while collapsed.)
  When a node is COLLAPSED:
    • All descendant heights are subtracted.
    • The delta = NodeHeight − current TotalHeight  (a negative number). }
var
  allowed: Boolean;
  childrenH: Integer;
begin
  if (Node = nil) or (Node = FRoot) then Exit;
  if not (nsHasChildren in Node^.States) then Exit;
  if AValue = (nsExpanded in Node^.States) then Exit;

  if AValue then
  begin
    // ── Expanding ──
    allowed := True;
    if Assigned(FOnExpanding) then FOnExpanding(Self, Node, allowed);
    if not allowed then Exit;

    InitChildren(Node);
    Include(Node^.States, nsExpanded);

    // Add the newly-visible descendant heights.
    // While collapsed, TotalHeight == NodeHeight.
    // ComputeExpandedSubtreeHeight(Node) = NodeHeight + sum(child heights).
    childrenH := ComputeExpandedSubtreeHeight(Node) - Integer(Node^.TotalHeight);
    if childrenH <> 0 then AdjustTotalHeight(Node, childrenH);

    if Assigned(FOnExpanded) then FOnExpanded(Self, Node);
  end
  else
  begin
    // ── Collapsing ──
    allowed := True;
    if Assigned(FOnCollapsing) then FOnCollapsing(Self, Node, allowed);
    if not allowed then Exit;

    // childrenH is negative: NodeHeight − TotalHeight (TotalHeight ≥ NodeHeight while expanded).
    // IMPORTANT: call AdjustTotalHeight BEFORE Exclude(nsExpanded), so that
    // AdjustTotalHeight can still climb past this node to its ancestors.
    // (AdjustTotalHeight stops climbing at the first non-expanded node; if we
    // cleared nsExpanded first, it would stop right here and leave root stale.)
    childrenH := Integer(Node^.NodeHeight) - Integer(Node^.TotalHeight);
    if childrenH <> 0 then AdjustTotalHeight(Node, childrenH);
    Exclude(Node^.States, nsExpanded);

    if Assigned(FOnCollapsed) then FOnCollapsed(Self, Node);
  end;
  InvalidateTreeLayout;
end;

procedure TTyTreeView.ToggleNode(Node: PTyTreeNode; AExpand: Boolean);
begin
  SetExpanded(Node, AExpand);
end;

{ ── A5 ── iterators ──────────────────────────────────────────────────────── }

function TTyTreeView.GetFirstChild(Node: PTyTreeNode): PTyTreeNode;
begin
  if Node = nil then Result := FRoot^.FirstChild
  else Result := Node^.FirstChild;
end;

function TTyTreeView.GetLastChild(Node: PTyTreeNode): PTyTreeNode;
begin
  if Node = nil then Result := FRoot^.LastChild
  else Result := Node^.LastChild;
end;

function TTyTreeView.GetNextSibling(Node: PTyTreeNode): PTyTreeNode;
begin
  if Node = nil then Result := nil
  else Result := Node^.NextSibling;
end;

function TTyTreeView.GetPrevSibling(Node: PTyTreeNode): PTyTreeNode;
begin
  if Node = nil then Result := nil
  else Result := Node^.PrevSibling;
end;

{ GetParent: returns nil when Node is a top-level node (its Parent is the hidden root).
  Mirrors VTV semantics: GetNodeParent returns nil for root-level nodes. }
function TTyTreeView.GetParent(Node: PTyTreeNode): PTyTreeNode;
begin
  if (Node = nil) or (Node = FRoot) then
    Result := nil
  else if Node^.Parent = FRoot then
    Result := nil     // top-level node — parent is the hidden root sentinel
  else if Node^.Parent = PTyTreeNode(Self) then
    Result := nil     // Node IS the root (shouldn't happen but be safe)
  else
    Result := Node^.Parent;
end;

{ GetNodeLevel: returns 0 for top-level nodes (direct children of the hidden root).
  Counts parent hops until we hit the hidden root or the sentinel. }
function TTyTreeView.GetNodeLevel(Node: PTyTreeNode): Integer;
var
  run: PTyTreeNode;
begin
  Result := 0;
  if (Node = nil) or (Node = FRoot) then Exit;
  run := Node^.Parent;
  while (run <> nil) and (run <> FRoot) and (run <> PTyTreeNode(Self)) do
  begin
    Inc(Result);
    run := run^.Parent;
  end;
end;

{ GetFirst: depth-first pre-order first node, inits it. }
function TTyTreeView.GetFirst: PTyTreeNode;
begin
  Result := FRoot^.FirstChild;
  if Result <> nil then InitNode(Result);
end;

{ GetNext: depth-first pre-order successor, inits any node we land on. }
function TTyTreeView.GetNext(Node: PTyTreeNode): PTyTreeNode;
begin
  if Node = nil then begin Result := nil; Exit; end;

  // Descend into children first
  if Node^.FirstChild <> nil then
  begin
    Result := Node^.FirstChild;
    InitNode(Result);
    Exit;
  end;

  // No children — try next sibling, then climb
  Result := Node;
  repeat
    if Result^.NextSibling <> nil then
    begin
      Result := Result^.NextSibling;
      InitNode(Result);
      Exit;
    end;
    Result := Result^.Parent;
    if (Result = FRoot) or (Result = PTyTreeNode(Self)) then
    begin
      Result := nil;
      Exit;
    end;
  until False;
end;

{ GetFirstVisibleNoInit: first screen-order visible node (no init side-effects). }
function TTyTreeView.GetFirstVisibleNoInit: PTyTreeNode;
begin
  Result := FRoot^.FirstChild;
  // Advance past any non-visible top-level nodes
  while (Result <> nil) and not (nsVisible in Result^.States) do
    Result := Result^.NextSibling;
end;

{ GetNextVisibleNoInit: screen-order successor, skipping collapsed subtrees.
  Never inits nodes — safe to call from paint / scroll. }
function TTyTreeView.GetNextVisibleNoInit(Node: PTyTreeNode): PTyTreeNode;
begin
  Result := Node;
  repeat
    if (nsExpanded in Result^.States) and (Result^.FirstChild <> nil) then
      Result := Result^.FirstChild
    else
      while Result <> nil do
      begin
        if Result^.NextSibling <> nil then
        begin
          Result := Result^.NextSibling;
          Break;
        end;
        Result := Result^.Parent;
        if Result = FRoot then
        begin
          Result := nil;
          Break;
        end;
      end;
  until (Result = nil) or (nsVisible in Result^.States);
end;

{ GetPreviousVisibleNoInit: reverse screen-order predecessor (no init).
  Walk to the previous sibling's last expanded descendant, or to the parent. }
function TTyTreeView.GetPreviousVisibleNoInit(Node: PTyTreeNode): PTyTreeNode;
var
  prev: PTyTreeNode;
begin
  if Node = nil then begin Result := nil; Exit; end;

  // Try the previous sibling (then go down into its last expanded descendant)
  if Node^.PrevSibling <> nil then
  begin
    Result := Node^.PrevSibling;
    // Descend into the last expanded child chain
    while (nsExpanded in Result^.States) and (Result^.LastChild <> nil) do
      Result := Result^.LastChild;
    // skip invisible (shouldn't happen in normal trees, but be safe)
    while (Result <> nil) and not (nsVisible in Result^.States) do
    begin
      prev := Result^.PrevSibling;
      if prev <> nil then Result := prev
      else begin Result := nil; Break; end;
    end;
    Exit;
  end;

  // No previous sibling — go to parent (unless parent is root)
  Result := Node^.Parent;
  if (Result = nil) or (Result = FRoot) or (Result = PTyTreeNode(Self)) then
    Result := nil;
end;

{ ── B3 ── position cache ────────────────────────────────────────────────── }

{ ValidateCache
  One O(visibleCount) pass building the FPositionCache array.
  A mark is pushed every TREE_CACHE_STEP visible nodes (including node #0).
  Called at the start of every GetNodeAt; only does work when FCacheValid=False.

  Safety: FCacheValid is cleared by InvalidateTreeLayout, which is called on
  every structural change (SetChildCount, DeleteNode, Clear, expand/collapse).
  So when ValidateCache runs, the tree is in its current canonical state.
  There is NO path that uses a stale cache: every GetNodeAt calls ValidateCache
  first, and ValidateCache rebuilds when FCacheValid=False. }
procedure TTyTreeView.ValidateCache;
var
  n:         PTyTreeNode;
  accTop:    Integer;  // accumulates absolute Y (named accTop to avoid conflict with TControl.Top)
  visIdx:    Integer;
  markCount: Integer;
begin
  if FCacheValid then Exit;

  { Rebuild from scratch. }
  SetLength(FPositionCache, 0);
  markCount := 0;

  accTop := 0;
  visIdx := 0;
  n := GetFirstVisibleNoInit;
  while n <> nil do
  begin
    { Push a mark every TREE_CACHE_STEP nodes (index 0, 2000, 4000, …). }
    if (visIdx mod TREE_CACHE_STEP) = 0 then
    begin
      SetLength(FPositionCache, markCount + 1);
      FPositionCache[markCount].Node    := n;
      FPositionCache[markCount].NodeTop := accTop;
      Inc(markCount);
    end;
    Inc(accTop, n^.NodeHeight);
    Inc(visIdx);
    n := GetNextVisibleNoInit(n);
  end;

  FCacheValid := True;
end;

{ FindInCache(Y)
  Binary-search FPositionCache for the index of the last mark whose Top <= Y.
  Returns -1 if Y is before the first mark or the cache is empty.
  The caller should treat -1 as "start from the root" (i.e. cache miss). }
function TTyTreeView.FindInCache(Y: Integer): Integer;
var
  lo, hi, mid: Integer;
begin
  Result := -1;
  if Length(FPositionCache) = 0 then Exit;
  if Y < FPositionCache[0].NodeTop then Exit;  // before the very first mark

  lo := 0;
  hi := High(FPositionCache);
  while lo <= hi do
  begin
    mid := (lo + hi) shr 1;
    if FPositionCache[mid].NodeTop <= Y then
    begin
      Result := mid;   // candidate — keep searching right for a closer mark
      lo := mid + 1;
    end
    else
      hi := mid - 1;
  end;
end;

{ ── B2 ── GetNodeAt(Y) — TotalHeight subtree-skip ──────────────────────── }

{ Maps an absolute vertical pixel offset Y (0 = top of the first visible node,
  i.e. the hidden root's own row is NOT counted) to the visible node covering it
  plus that node's absolute top in ANodeTop.  Returns nil if Y < 0 or past end.

  B3 cache: ValidateCache is called first to ensure FPositionCache is current.
  FindInCache returns the mark index whose Top is the nearest at-or-below Y.
  The walk then STARTS from that mark rather than from root, bounding the
  per-call sibling scan to at most TREE_CACHE_STEP nodes.

  The correctness of the cache is guaranteed by the invariant:
    • FCacheValid is cleared by every structural mutation (InvalidateTreeLayout).
    • ValidateCache rebuilds before any cache read.
  Therefore the marks always correspond to the current visible-node sequence.

  Algorithm (bounded by TREE_CACHE_STEP after the cache-start, plus depth):
  • Call ValidateCache; binary-search FPositionCache with FindInCache(Y).
  • If a mark is found, seed (node, runTop) from the mark; otherwise use root.
  • From the seeded node, perform the same subtree-skip walk as in B2.
  • Climb-back logic mirrors GetNextVisibleNoInit exactly.

  FLastGetNodeAtVisits counts how many node-iterations the walk makes;
  it is exposed read-only for the performance-invariant test (TTreePerfTest). }
function TTyTreeView.GetNodeAt(Y: Integer; out ANodeTop: Integer): PTyTreeNode;
var
  node, climb: PTyTreeNode;
  runTop, h:   Integer;
  cacheIdx:    Integer;
begin
  Result   := nil;
  ANodeTop := 0;
  FLastGetNodeAtVisits := 0;
  if Y < 0 then Exit;

  { B3: rebuild cache if dirty, then find the nearest mark at or below Y. }
  ValidateCache;
  cacheIdx := FindInCache(Y);
  if cacheIdx >= 0 then
  begin
    node   := FPositionCache[cacheIdx].Node;
    runTop := FPositionCache[cacheIdx].NodeTop;
  end
  else
  begin
    { No suitable mark (cache empty or Y before first mark) — start from root. }
    node   := FRoot^.FirstChild;
    runTop := 0;
  end;

  while node <> nil do
  begin
    Inc(FLastGetNodeAtVisits);

    // Skip non-visible nodes (they have no screen extent); treat like a missing node.
    if not (nsVisible in node^.States) then
    begin
      // Advance to NextSibling (or climb if at end of list)
      if node^.NextSibling <> nil then
      begin
        node := node^.NextSibling;
        Continue;
      end;
      // Climb-back: walk up to find a parent with a NextSibling
      climb := node^.Parent;
      node  := nil;
      while (climb <> nil) and (climb <> FRoot) do
      begin
        if climb^.NextSibling <> nil then
        begin
          node := climb^.NextSibling;
          Break;
        end;
        climb := climb^.Parent;
      end;
      Continue;
    end;

    h := node^.NodeHeight;

    // Does Y land in this node's own row?
    if Y < runTop + h then
    begin
      Result   := node;
      ANodeTop := runTop;
      Exit;
    end;

    // Does Y land inside this node's expanded subtree?
    if (nsExpanded in node^.States) and (node^.FirstChild <> nil)
       and (Y < runTop + Integer(node^.TotalHeight)) then
    begin
      // Descend: advance past the node's own row and go into children.
      Inc(runTop, h);
      node := node^.FirstChild;
      Continue;
    end;

    // Skip this node's span — TotalHeight for an expanded node (skipping the subtree in O(1)),
    // or just NodeHeight for a leaf or collapsed node.
    if (nsExpanded in node^.States) and (node^.FirstChild <> nil) then
      Inc(runTop, Integer(node^.TotalHeight))
    else
      Inc(runTop, h);

    // Advance to next sibling.  If the sibling list is exhausted, climb back to the
    // nearest ancestor that still has a NextSibling — mirroring GetNextVisibleNoInit.
    if node^.NextSibling <> nil then
    begin
      node := node^.NextSibling;
      Continue;
    end;

    // Climb-back: walk up until we find an ancestor with a NextSibling, or reach FRoot.
    climb := node^.Parent;
    node  := nil;
    while (climb <> nil) and (climb <> FRoot) do
    begin
      if climb^.NextSibling <> nil then
      begin
        node := climb^.NextSibling;
        Break;
      end;
      climb := climb^.Parent;
    end;
    // If node is still nil here, all siblings+ancestors exhausted → loop exits.
  end;
end;

{ ── ③d A1 ── shared cell geometry ───────────────────────────────────────── }

{ InternalCellRect — the single source of per-cell x-geometry, shared by
  RenderTo (paint) and GetCellRect (measure).

  Inputs are all DEVICE-pixel: CR is the content rect (RenderTo's CR /
  ContentRect — top already past the header band), ARowTop/ARowH are the device
  top/height of the node's row, AColumn is the requested column (or -1 / the
  main column for the whole main cell), APPI is the paint PPI.

  Output ACellRect spans the full device column cell:
    • 0-column mode → CR.Left .. CR.Right (AColumn ignored).
    • multi-column  → CR.Left + Scale(col.Left) + FOffsetX
                      .. + Scale(col.Width)
      (verbatim the colCellLeft/colCellRight formula RenderTo paints with).
  The vertical extent is always [ARowTop .. ARowTop + ARowH].

  Returns False only when a REAL column index does not resolve to a visible
  column (out of range / coVisible off); the main/0-column cases always succeed. }
function TTyTreeView.InternalCellRect(const CR: TRect;
  ARowTop, ARowH, AColumn, APPI: Integer; out ACellRect: TRect): Boolean;
var
  col: TTyTreeColumn;
  colObj: TObject;
  effCol: Integer;
  cLeft, cRight: Integer;
begin
  Result   := False;
  ACellRect := Rect(0, 0, 0, 0);

  { 0-column (③a) mode: the cell IS the content row rect; AColumn is ignored. }
  if (FHeader = nil) or (FHeader.Columns.Count = 0) then
  begin
    ACellRect := Rect(CR.Left, ARowTop, CR.Right, ARowTop + ARowH);
    Result := True;
    Exit;
  end;

  { Multi-column: -1 → the main column's own cell. }
  effCol := AColumn;
  if effCol = NoColumn then
    effCol := FHeader.MainColumn;

  if (effCol < 0) or (effCol >= FHeader.Columns.Count) then Exit;
  colObj := FHeader.Columns.Items[effCol];
  if not (colObj is TTyTreeColumn) then Exit;
  col := TTyTreeColumn(colObj);
  if not (coVisible in col.Options) then Exit;

  { Verbatim the RenderTo cell-left/right math (device px, scroll-adjusted). }
  cLeft  := CR.Left + MulDiv(col.Left,  APPI, 96) + FOffsetX;
  cRight := cLeft   + MulDiv(col.Width, APPI, 96);
  ACellRect := Rect(cLeft, ARowTop, cRight, ARowTop + ARowH);
  Result := True;
end;

{ GetCellRect — device-pixel rect of Node's cell in Column (see the interface
  comment). Computes the node's device row-top by REPRODUCING RenderTo's own
  walk exactly: seed from GetNodeAt(max(0,-FOffsetY)) (the first on-screen node,
  with rowTop = CR.Top - Scale(firstNodeY - firstTop)), then advance / retreat
  by Scale(NodeHeight) per visible row to the target — byte-identical arithmetic
  to the paint loop's per-row accumulation, so no rounding drift at any PPI.
  Never calls InitNode (uses the *NoInit visible iterators only). }
function TTyTreeView.GetCellRect(Node: PTyTreeNode; Column: Integer;
  out ACellRect: TRect): Boolean;
var
  PPI: Integer;
  CR: TRect;
  firstNodeY, firstTop: Integer;
  seed, n: PTyTreeNode;
  rowTop, rowH: Integer;
  found: Boolean;
begin
  Result    := False;
  ACellRect := Rect(0, 0, 0, 0);

  { Not a real, visible node. }
  if (Node = nil) or (Node = FRoot) then Exit;
  if not (nsVisible in Node^.States) then Exit;

  { Keep scrollbar visibility / offset clamping current — exactly what RenderTo
    does at the top of every paint, so CR (and thus the rect) matches the paint. }
  UpdateScrollBars;

  PPI := Font.PixelsPerInch;
  CR  := ContentRect;   // identical to RenderTo's CR (padding + scrollbars + header inset)

  { Seed the row-top walk the SAME way RenderTo does. }
  firstNodeY := -FOffsetY;
  if firstNodeY < 0 then firstNodeY := 0;
  seed := GetNodeAt(firstNodeY, firstTop);
  if seed = nil then Exit;   // empty / fully scrolled past
  rowTop := CR.Top - MulDiv(firstNodeY - firstTop, PPI, 96);

  found := False;
  if seed = Node then
    found := True
  else
  begin
    { Target is after the seed: walk forward, advancing rowTop per row
      (mirrors `Inc(rowTop, rowH)` in the paint loop). }
    n := seed;
    while n <> nil do
    begin
      Inc(rowTop, MulDiv(n^.NodeHeight, PPI, 96));
      n := GetNextVisibleNoInit(n);
      if n = Node then begin found := True; Break; end;
    end;

    { Not forward — target is above the first on-screen node: retreat from the
      seed, subtracting each predecessor's scaled height. }
    if not found then
    begin
      rowTop := CR.Top - MulDiv(firstNodeY - firstTop, PPI, 96);
      n := seed;
      while n <> nil do
      begin
        n := GetPreviousVisibleNoInit(n);
        if n = nil then Break;
        Dec(rowTop, MulDiv(n^.NodeHeight, PPI, 96));
        if n = Node then begin found := True; Break; end;
      end;
    end;
  end;

  if not found then Exit;   // node not in the visible sequence

  rowH := MulDiv(Node^.NodeHeight, PPI, 96);

  { Off-screen vertically (row entirely above / below the node area) → not visible. }
  if rowTop + rowH <= CR.Top then Exit;
  if rowTop >= CR.Bottom then Exit;

  Result := InternalCellRect(CR, rowTop, rowH, Column, PPI, ACellRect);
end;

{ ── C3 ── RenderTo / Paint ──────────────────────────────────────────────── }

{ RenderTo — paint the VISIBLE window only (performance is the point).

  Algorithm:
  1. DrawFrame for the TyTreeView container.
  2. Compute ContentRect (frame interior minus padding and visible scrollbar(s)).
  3. Empty tree → draw EmptyListMessage centred, done.
  4. Find first on-screen node via GetNodeAt(-FOffsetY). The node may start
     ABOVE ContentRect.Top (sub-row remainder); the initial rowTop accounts for
     the partial row already scrolled out of view.
  5. Loop over visible nodes until rowTop >= ContentRect.Bottom:
     • InitNode so OnGetText / nsHasChildren / OnGetImageIndex are ready.
     • Row background: resolve TyTreeNode style with the right state set.
     • Indent + expand button + image + caption, all in scaled pixels.
     • Tree lines (simplified: vertical guide + elbow per indent slot).
     • Accumulate FRangeX for the horizontal scrollbar.
  6. EndPaint; after the loop call UpdateScrollBars if FRangeX changed. }
procedure TTyTreeView.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, NodeStyle: TTyStyleSet;
  W, H: Integer;
  CR: TRect;   // content rect (frame interior minus scrollbars)
  SBThick: Integer;
  node: PTyTreeNode;
  rowTop, firstTop, firstNodeY: Integer;
  rowH: Integer;
  rowRect, bgRect, textRect, btnRect: TRect;
  level, indentPx, btnSlotW, imgSlotW: Integer;
  nodeStates: TTyStateSet;
  txt: string;
  ghosted: Boolean;
  imgIdx: Integer;
  captionX: Integer;
  rangeXNew: Integer;
  inset, insetLogical: Integer;
  savedClip: TRect;
  anc: PTyTreeNode;
  ancLevel, ancMidX, ancMidY, ancSlotX: Integer;
  measW: Integer;
  contentLeft: Integer;
  gSz, slotBaseX: Integer;
  usedImgSlotW: Integer;
  { ── C (columns) variables ───────────────────────────────────────────────── }
  useColumns: Boolean;          // True when Columns.Count > 0
  hasHeader: Boolean;           // True when hoVisible and useColumns
  headerH: Integer;             // device-px header band height
  headerBandRect: TRect;        // device rect for the header band
  headerBgStyle, headerSecStyle: TTyStyleSet;
  colCount, posIdx, colIdx: Integer;
  col: TTyTreeColumn;
  cellLeft, cellRight: Integer;
  cellRect, clipR: TRect;
  colCellLeft, colCellRight: Integer;
  colCaptionX, colMargin: Integer;
  colTxt: string;
  sortGlyphSize: Integer;
  colAlign: TAlignment;
  sortBandR: TRect;
  accentPx: TBGRAPixel;         // theme accent for the drag ghost/drop-mark
  mainColBase: Integer;
  { B2: checkbox slot variables }
  cbSlotW: Integer;            // device-px width of the checkbox slot (P.Scale(16))
  cbStyle: TTyStyleSet;        // resolved TyTreeCheckBox style
  cbBoxRect: TRect;            // device rect of the box/circle within the slot
  cbBoxSize: Integer;          // device-px side of the drawn box/circle
  usedCbSlotW: Integer;        // 0 when checkbox off/ctNone; cbSlotW otherwise
  { Node images are drawn via GDI onto ACanvas AFTER EndPaint (see below), so
    collect their device-coord positions during the row loop instead of drawing
    them into the BGRA layer. Drawing an ImageList into TTyPainter.Bitmap.Canvas
    worked on Windows (the LCL RawImage→bitmap conversion aliases the BGRA data
    buffer there) but was silently dropped on Qt/GTK, where the bitmap is a
    separate buffer the EndPaint rebuild-from-data discards. }
  pendingIcons: array of record X, Y, Idx: Integer; end;
  pendingCount: Integer;
  iIcon, savedDC: Integer;
  { ③d D1: per-cell owner-draw — collected during the row loop, drawn onto
    ACanvas AFTER P.EndPaint (the same post-composite path as pendingIcons,
    because any GDI draw to ACanvas DURING RenderTo is erased by the EndPaint
    blit of the BGRA layer). Rect is painter-local (CR-space, 0-based); the
    post-EndPaint draw offsets it by ARect just like the icons. ownerDrawCell
    is True only when this exact cell is being fully replaced by OnDrawNode. }
  ownerDrawActive: Boolean;   // toOwnerDraw in FOptions and OnDrawNode assigned
  ownerDrawCell:   Boolean;   // per-cell: this cell is replaced by OnDrawNode
  pendingDrawNode: array of record Node: PTyTreeNode; Col: Integer; R: TRect; end;
  pendingDrawCount: Integer;
  pendingAfter: array of record Node: PTyTreeNode; Col: Integer; R: TRect; end;
  pendingAfterCount: Integer;
  iCb: Integer;
begin
  UpdateScrollBars;   // keep scrollbar range current (cheap; no-op when clean)

  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;

    pendingCount := 0;
    SetLength(pendingIcons, 0);

    { ③d D1: owner-draw collection state }
    ownerDrawActive   := (toOwnerDraw in FOptions) and Assigned(FOnDrawNode);
    pendingDrawCount  := 0;
    SetLength(pendingDrawNode, 0);
    pendingAfterCount := 0;
    SetLength(pendingAfter, 0);

    W := ARect.Right  - ARect.Left;
    H := ARect.Bottom - ARect.Top;

    DrawFrame(P, Rect(0, 0, W, H), S);

    { Content rect: frame interior minus padding and visible scrollbar(s). }
    SBThick := MulDiv(TyScrollbarSize, APPI, 96);
    CR := Rect(
      P.Scale(S.Padding.Left),
      P.Scale(S.Padding.Top),
      W - P.Scale(S.Padding.Right),
      H - P.Scale(S.Padding.Bottom)
    );
    if (FVScroll <> nil) and FVScroll.Visible then
      Dec(CR.Right, SBThick);
    if (FHScroll <> nil) and FHScroll.Visible then
      Dec(CR.Bottom, SBThick);

    { Content origin: shifted left by the horizontal scroll offset (FOffsetX <= 0).
      Row backgrounds, the right-clip and the clip rect stay anchored to the
      VISIBLE frame (CR); only content x-positions use contentLeft. }
    contentLeft := CR.Left + FOffsetX;

    { ── Column guard: are we in multi-column mode? ─────────────────────────── }
    useColumns := (FHeader <> nil) and (FHeader.Columns.Count > 0);
    hasHeader  := useColumns and (hoVisible in FHeader.Options);
    headerH    := 0;
    if hasHeader then
    begin
      headerH := P.Scale(FHeader.Height);
      { Inset CR.Top so node rows start BELOW the header band.
        The header band occupies [CR.Top_original .. CR.Top_original + headerH].
        After this Inc, CR.Top is the top of the node area. }
      Inc(CR.Top, headerH);
      { Ensure positions are current before paint }
      FHeader.Columns.UpdatePositions;
    end
    else if useColumns then
      FHeader.Columns.UpdatePositions;

    { ── Empty tree ───────────────────────────────────────────────────────── }
    { Handled AFTER the header band paints (at the first-row-nil branch below) so
      an empty multi-column tree still shows its column headers. }

    { Row chrome inset: row fills must not touch the border's anti-aliased edge.
      Mirror the ListBox pattern exactly. }
    insetLogical := S.BorderWidth;
    if (tpOutline in S.Present) and (S.OutlineWidth > 0) then
      if S.OutlineOffset + S.OutlineWidth > insetLogical then
        insetLogical := S.OutlineOffset + S.OutlineWidth;
    if insetLogical > 0 then Inc(insetLogical);
    inset := P.Scale(insetLogical);

    savedClip := P.Bitmap.ClipRect;
    P.Bitmap.ClipRect := Rect(inset, inset, W - inset, H - inset);

    { ── C2: Header band paint (BEFORE node area) ─────────────────────────── }
    if hasHeader then
    begin
      { Band rect spans the full content width, at the top of CR (before headerH offset) }
      headerBandRect := Rect(CR.Left, CR.Top - headerH, CR.Right, CR.Top);
      { Resolve styles — tolerate absent typeKeys (fallback to tree tokens) }
      headerBgStyle  := ActiveController.Model.ResolveStyle('TyTreeHeader', '', []);
      headerSecStyle := ActiveController.Model.ResolveStyle('TyTreeHeaderSection', '', []);

      { Fill header band background }
      if tpBackground in headerBgStyle.Present then
        P.FillBackground(headerBandRect, headerBgStyle.Background, 0)
      else
      begin
        { Fallback: use a lightened border color or the tree background }
        P.FillBackground(headerBandRect, S.Background, 0);
      end;

      { Per-column header cells }
      colCount := FHeader.Columns.Count;
      for posIdx := 0 to colCount - 1 do
      begin
        col := FHeader.Columns.ColumnByPosition(posIdx);
        if col = nil then Continue;
        if not (coVisible in col.Options) then Continue;

        colIdx := col.Index;

        { Column cell x range (scroll-adjusted, device pixels).
          col.Left is the absolute left in logical px; scale to device. }
        cellLeft  := CR.Left + P.Scale(col.Left) + FOffsetX;
        cellRight := cellLeft + P.Scale(col.Width);

        { Skip cells entirely off-screen }
        if cellRight <= CR.Left then Continue;
        if cellLeft  >= CR.Right then Continue;

        { Header cell rect }
        cellRect := Rect(cellLeft, headerBandRect.Top, cellRight, headerBandRect.Bottom);

        { Clip to visible area }
        clipR := cellRect;
        if clipR.Left  < CR.Left  then clipR.Left  := CR.Left;
        if clipR.Right > CR.Right then clipR.Right := CR.Right;

        { Fill cell background — hover if this is the hovered column,
          else transparent (inherits band bg) }
        if (hoHotTrack in FHeader.Options) and (colIdx = NoColumn) then
        begin
          { NoColumn = -1, so this branch never fires — FHotHeaderColumn would go here in Phase D }
        end;
        if tpBackground in headerSecStyle.Present then
          P.FillBackground(clipR, headerSecStyle.Background, 0);

        { Reserve space for sort glyph when this is the sort column }
        sortGlyphSize := 0;
        if (hoShowSortGlyphs in FHeader.Options) and
           (colIdx = FHeader.SortColumn) then
          sortGlyphSize := P.Scale(10);

        { Column caption rect }
        colMargin := P.Scale(4);
        colCaptionX := clipR.Left + colMargin;

        textRect := Rect(colCaptionX,
                         headerBandRect.Top,
                         clipR.Right - colMargin - sortGlyphSize,
                         headerBandRect.Bottom);

        if textRect.Left < textRect.Right then
        begin
          { Determine caption alignment }
          colAlign := col.CaptionAlignment;
          { Resolve text color }
          if tpTextColor in headerSecStyle.Present then
            P.DrawText(textRect, col.Text,
              headerSecStyle.FontName, ResolveFontSize(headerSecStyle),
              headerSecStyle.FontWeight,
              headerSecStyle.TextColor, colAlign, tlCenter, True)
          else
            P.DrawText(textRect, col.Text,
              S.FontName, ResolveFontSize(S), S.FontWeight,
              S.TextColor, colAlign, tlCenter, True);
        end;

        { Sort glyph in sort column }
        if sortGlyphSize > 0 then
        begin
          { Draw an arrow glyph at the right of the header cell using DrawGlyph }
          sortBandR := Rect(clipR.Right - sortGlyphSize - colMargin,
                            headerBandRect.Top + P.Scale(2),
                            clipR.Right - colMargin,
                            headerBandRect.Bottom - P.Scale(2));
          if sortBandR.Right > sortBandR.Left then
          begin
            if tpTextColor in headerSecStyle.Present then
              colTxt := ''  { reuse colTxt as a scratch — not used here }
            else
              colTxt := '';
            if FHeader.SortDirection = sdAscending then
            begin
              if tpTextColor in headerSecStyle.Present then
                P.DrawGlyph(sortBandR, tgArrowUp, headerSecStyle.TextColor, P.Scale(1), 1)
              else
                P.DrawGlyph(sortBandR, tgArrowUp, S.TextColor, P.Scale(1), 1);
            end
            else
            begin
              if tpTextColor in headerSecStyle.Present then
                P.DrawGlyph(sortBandR, tgArrowDown, headerSecStyle.TextColor, P.Scale(1), 1)
              else
                P.DrawGlyph(sortBandR, tgArrowDown, S.TextColor, P.Scale(1), 1);
            end;
          end;
        end;

        { Right-edge divider line (not on the last visible column) }
        if posIdx < colCount - 1 then
        begin
          { Check if next column is visible }
          P.Bitmap.DrawLine(cellRight - 1, headerBandRect.Top,
                            cellRight - 1, headerBandRect.Bottom,
                            TyColorToBGRA(S.BorderColor), False);
        end;
      end;

      { Bottom border of header band }
      P.Bitmap.DrawLine(CR.Left, CR.Top, CR.Right, CR.Top,
                        TyColorToBGRA(S.BorderColor), False);

      { D3: drag-reorder overlay — ghost of dragged column + drop-mark caret }
      if FDragging and (FDragColumn >= 0) and (FDragColumn < FHeader.Columns.Count) then
      begin
        { Drag overlay accent from the THEME (TyTreeNode:selected bg = --accent),
          never a hard-coded color. NodeStyle is free here — the node loop runs later. }
        NodeStyle := ActiveController.Model.ResolveStyle('TyTreeNode', '', [tysSelected]);
        if tpBackground in NodeStyle.Present then
          accentPx := TyColorToBGRA(NodeStyle.Background.Color)
        else
          accentPx := TyColorToBGRA(S.BorderColor);
        { Ghost: draw a semi-transparent filled rect over the dragged column's
          header cell at its current position (not yet moved) }
        col := FHeader.Columns.Items[FDragColumn] as TTyTreeColumn;
        cellLeft  := CR.Left + P.Scale(col.Left) + FOffsetX;
        cellRight := cellLeft + P.Scale(col.Width);
        { Clamp to visible area }
        if cellLeft  < CR.Left  then cellLeft  := CR.Left;
        if cellRight > CR.Right then cellRight := CR.Right;
        if cellLeft < cellRight then
        begin
          cellRect := Rect(cellLeft, headerBandRect.Top, cellRight, headerBandRect.Bottom);
          { Ghost fill: accent color at ~40% opacity over the header }
          P.Bitmap.FillRect(cellRect.Left, cellRect.Top,
                            cellRect.Right, cellRect.Bottom,
                            BGRA(accentPx.red, accentPx.green, accentPx.blue, 100));  { accent ghost, ~40% alpha }
        end;

        { Drop-mark: a 2px vertical caret at the target position boundary }
        if (FDragTargetPos >= 0) and (FDragTargetPos < FHeader.Columns.Count) then
        begin
          col := FHeader.Columns.ColumnByPosition(FDragTargetPos);
          if col <> nil then
          begin
            { Insert caret at the LEFT edge of the target column's position }
            cellLeft := CR.Left + P.Scale(col.Left) + FOffsetX;
            if cellLeft < CR.Left  then cellLeft := CR.Left;
            if cellLeft > CR.Right then cellLeft := CR.Right;
            { Draw a 2px wide vertical accent bar }
            P.Bitmap.DrawLine(cellLeft,     headerBandRect.Top,
                              cellLeft,     headerBandRect.Bottom,
                              accentPx, False);
            P.Bitmap.DrawLine(cellLeft + 1, headerBandRect.Top,
                              cellLeft + 1, headerBandRect.Bottom,
                              accentPx, False);
          end;
        end;
      end;
    end;

    { ── First on-screen node ─────────────────────────────────────────────── }
    firstNodeY := -FOffsetY;
    if firstNodeY < 0 then firstNodeY := 0;
    node := GetNodeAt(firstNodeY, firstTop);
    if node = nil then
    begin
      { Empty tree (or fully scrolled past): draw the empty-list message in the
        node area, BELOW the header band which has already painted above. }
      if (FRoot^.FirstChild = nil) and (FEmptyListMessage <> '') then
      begin
        NodeStyle := ActiveController.Model.ResolveStyle('TyTreeNode', '', []);
        P.DrawText(CR, FEmptyListMessage, S.FontName, ResolveFontSize(S), S.FontWeight,
          NodeStyle.TextColor, taCenter, tlCenter, True);
      end;
      P.Bitmap.ClipRect := savedClip;
      P.EndPaint;
      Exit;
    end;
    { The first row may be partially scrolled above the viewport.
      rowTop = device-Y where the first row's TOP pixel should be drawn.
      firstNodeY and firstTop are LOGICAL (node heights), so the sub-row
      remainder (firstNodeY - firstTop) must be scaled to device pixels before
      subtracting from the device-pixel CR.Top. }
    rowTop := CR.Top - P.Scale(firstNodeY - firstTop);

    rangeXNew := FRangeX;

    btnSlotW := P.Scale(FIndent);   // one Indent-wide slot for the expand button
    imgSlotW := P.Scale(FIndent);   // one Indent-wide slot for the image

    { ── Per-row paint loop ───────────────────────────────────────────────── }
    while (node <> nil) and (rowTop < CR.Bottom) do
    begin
      InitNode(node);   // idempotent; fires OnGetText/nsHasChildren/etc. once

      rowH    := P.Scale(node^.NodeHeight);
      rowRect := Rect(CR.Left, rowTop, CR.Right, rowTop + rowH);

      { ── Row background ─────────────────────────────────────────────────── }
      nodeStates := [];
      if nsSelected in node^.States then
        nodeStates := [tysSelected]
      else if FHotTrack and (node = FHotNode) then
        nodeStates := [tysHover];

      NodeStyle := ActiveController.Model.ResolveStyle('TyTreeNode', '', nodeStates);

      if tpBackground in NodeStyle.Present then
      begin
        bgRect := rowRect;
        P.FillBackground(bgRect, NodeStyle.Background, 0);
      end;

      { ── X accumulation: level → indent ─────────────────────────────────── }
      level    := GetNodeLevel(node);
      indentPx := P.Scale((level + Ord(FShowRoot)) * FIndent);

      if useColumns then
      begin
        { ── C1: Multi-column paint branch ──────────────────────────────────
          Guard: only runs when Columns.Count > 0.
          The ③a single-column path is below (in the else branch). }

        colCount := FHeader.Columns.Count;
        for posIdx := 0 to colCount - 1 do
        begin
          col := FHeader.Columns.ColumnByPosition(posIdx);
          if col = nil then Continue;
          if not (coVisible in col.Options) then Continue;

          colIdx := col.Index;

          { Column cell x range (scroll-adjusted, device pixels).
            ③d A1: derived from the SHARED InternalCellRect so the painted cell
            and GetCellRect(node, colIdx) are byte-identical (single source of
            geometry). The result equals the old inline
              CR.Left + P.Scale(col.Left) + FOffsetX .. + P.Scale(col.Width). }
          if not InternalCellRect(CR, rowTop, rowH, colIdx, APPI, cellRect) then
            Continue;
          colCellLeft  := cellRect.Left;
          colCellRight := cellRect.Right;

          { Skip cells entirely outside the visible content rect }
          if colCellRight <= CR.Left then Continue;
          if colCellLeft  >= CR.Right then Continue;

          { Clip painter to this cell's visible x range }
          clipR := Rect(colCellLeft, rowTop, colCellRight, rowTop + rowH);
          if clipR.Left  < CR.Left  then clipR.Left  := CR.Left;
          if clipR.Right > CR.Right then clipR.Right := CR.Right;
          P.Bitmap.ClipRect := clipR;

          { ③d D1: this cell is owner-drawn (default text/image skipped) when
            toOwnerDraw + OnDrawNode are active. cellRect is the SHARED device
            rect (== GetCellRect(node, colIdx)) collected for the post-EndPaint
            callback; the row bg + tree chrome still paint underneath. }
          ownerDrawCell := ownerDrawActive;
          if ownerDrawCell then
          begin
            if pendingDrawCount = Length(pendingDrawNode) then
              SetLength(pendingDrawNode, pendingDrawCount + 32);
            pendingDrawNode[pendingDrawCount].Node := node;
            pendingDrawNode[pendingDrawCount].Col  := colIdx;
            pendingDrawNode[pendingDrawCount].R    := cellRect;
            Inc(pendingDrawCount);
          end;
          if Assigned(FOnAfterCellPaint) then
          begin
            if pendingAfterCount = Length(pendingAfter) then
              SetLength(pendingAfter, pendingAfterCount + 32);
            pendingAfter[pendingAfterCount].Node := node;
            pendingAfter[pendingAfterCount].Col  := colIdx;
            pendingAfter[pendingAfterCount].R    := cellRect;
            Inc(pendingAfterCount);
          end;

          if colIdx = FHeader.MainColumn then
          begin
            { ── Main column: draw ③a chrome (tree-lines + button + image) ── }
            { mainColBase is the left of the main column cell (like contentLeft in ③a) }
            mainColBase := colCellLeft;

            { Tree lines (anchored at mainColBase) }
            if FShowTreeLines and (level > 0) then
            begin
              anc := node^.Parent;
              while (anc <> nil) and (anc <> FRoot) and (anc <> PTyTreeNode(Self)) do
              begin
                ancLevel := GetNodeLevel(anc);
                ancSlotX := mainColBase
                            + P.Scale((ancLevel + Ord(FShowRoot)) * FIndent)
                            - (btnSlotW shr 1);
                if anc^.NextSibling <> nil then
                  P.Bitmap.DrawLine(ancSlotX, rowTop, ancSlotX, rowTop + rowH,
                    TyColorToBGRA(S.BorderColor), False);
                anc := anc^.Parent;
              end;
              ancMidX := mainColBase
                         + P.Scale((level - 1 + Ord(FShowRoot)) * FIndent + FIndent)
                         - (btnSlotW shr 1);
              ancMidY := rowTop + rowH div 2;
              P.Bitmap.DrawLine(ancMidX, rowTop,    ancMidX, ancMidY,
                TyColorToBGRA(S.BorderColor), False);
              P.Bitmap.DrawLine(ancMidX, ancMidY,   mainColBase + indentPx, ancMidY,
                TyColorToBGRA(S.BorderColor), False);
              if node^.NextSibling <> nil then
                P.Bitmap.DrawLine(ancMidX, ancMidY, ancMidX, rowTop + rowH,
                  TyColorToBGRA(S.BorderColor), False);
            end;

            { Expand button (anchored at mainColBase) }
            if FShowButtons and (nsHasChildren in node^.States) then
            begin
              gSz := btnSlotW;
              if rowH < gSz then gSz := rowH;
              slotBaseX := mainColBase + indentPx - btnSlotW + (btnSlotW - gSz) div 2;
              btnRect := Rect(
                slotBaseX,
                rowTop + (rowH - gSz) div 2,
                slotBaseX + gSz,
                rowTop + (rowH - gSz) div 2 + gSz
              );
              if btnRect.Right  <= btnRect.Left  then btnRect.Right  := btnRect.Left  + 4;
              if btnRect.Bottom <= btnRect.Top   then btnRect.Bottom := btnRect.Top   + 4;
              if nsExpanded in node^.States then
                P.DrawGlyph(btnRect, tgChevronDown, NodeStyle.TextColor, P.Scale(1), 2)
              else
                P.DrawGlyph(btnRect, tgChevronRight, NodeStyle.TextColor, P.Scale(1), 2);
            end;

            { Image (main column only) }
            { B2: Checkbox slot (main column, after expand button, before image) }
            captionX := mainColBase + indentPx;
            usedCbSlotW := 0;
            if (toCheckSupport in FOptions) and (node^.CheckType <> ctNone) then
            begin
              cbSlotW     := P.Scale(16);
              usedCbSlotW := cbSlotW;
              { Resolve checkbox style — fall back gracefully if typeKey absent }
              if node^.CheckState = csChecked then
                cbStyle := ActiveController.Model.ResolveStyle('TyTreeCheckBox', '', [tysActive])
              else if nsSelected in node^.States then
                cbStyle := ActiveController.Model.ResolveStyle('TyTreeCheckBox', '', [tysSelected])
              else
                cbStyle := ActiveController.Model.ResolveStyle('TyTreeCheckBox', '', []);
              cbBoxSize := P.Scale(12);
              if cbBoxSize > rowH - P.Scale(2) then cbBoxSize := rowH - P.Scale(2);
              if cbBoxSize < 4 then cbBoxSize := 4;
              cbBoxRect := Rect(
                captionX + (cbSlotW - cbBoxSize) div 2,
                rowTop + (rowH - cbBoxSize) div 2,
                captionX + (cbSlotW - cbBoxSize) div 2 + cbBoxSize,
                rowTop + (rowH - cbBoxSize) div 2 + cbBoxSize);
              { FIX 4: draw rectangular box background + border ONLY for checkbox
                types; ctRadioButton draws its own circle below (no square corners). }
              if node^.CheckType in [ctCheckBox, ctTriStateCheckBox] then
              begin
                if tpBackground in cbStyle.Present then
                  P.FillBackground(cbBoxRect, cbStyle.Background, cbStyle.BorderRadius)
                else
                  P.FillBackground(cbBoxRect, S.Background, 2);
                if tpBorderColor in cbStyle.Present then
                  P.StrokeBorder(cbBoxRect, cbStyle.BorderRadius, cbStyle.BorderWidth, cbStyle.BorderColor)
                else
                  P.StrokeBorder(cbBoxRect, 2, 1, S.BorderColor);
              end;
              { Draw glyph by CheckType + CheckState }
              case node^.CheckType of
                ctCheckBox, ctTriStateCheckBox:
                begin
                  if node^.CheckState = csChecked then
                  begin
                    if tpTextColor in cbStyle.Present then
                      P.DrawGlyph(cbBoxRect, tgCheck, cbStyle.TextColor, 2)
                    else
                      P.DrawGlyph(cbBoxRect, tgCheck, NodeStyle.TextColor, 2);
                  end
                  else if node^.CheckState = csMixed then
                  begin
                    if tpTextColor in cbStyle.Present then
                      P.Bitmap.FillRect(
                        cbBoxRect.Left + P.Scale(3), cbBoxRect.Top + P.Scale(3),
                        cbBoxRect.Right - P.Scale(3), cbBoxRect.Bottom - P.Scale(3),
                        TyColorToBGRA(cbStyle.TextColor))
                    else
                      P.Bitmap.FillRect(
                        cbBoxRect.Left + P.Scale(3), cbBoxRect.Top + P.Scale(3),
                        cbBoxRect.Right - P.Scale(3), cbBoxRect.Bottom - P.Scale(3),
                        TyColorToBGRA(S.TextColor));
                  end;
                  { csUnchecked: nothing extra }
                end;
                ctRadioButton:
                begin
                  { Draw circle only — no square box (FIX 4: prevents corner artifact) }
                  if tpBackground in cbStyle.Present then
                    P.FillBackground(cbBoxRect, cbStyle.Background, cbBoxSize div 2)
                  else
                    P.FillBackground(cbBoxRect, S.Background, cbBoxSize div 2);
                  if tpBorderColor in cbStyle.Present then
                    P.StrokeBorder(cbBoxRect, cbBoxSize div 2, cbStyle.BorderWidth, cbStyle.BorderColor)
                  else
                    P.StrokeBorder(cbBoxRect, cbBoxSize div 2, 1, S.BorderColor);
                  if node^.CheckState = csChecked then
                  begin
                    if tpTextColor in cbStyle.Present then
                      P.DrawGlyph(cbBoxRect, tgRadioDot, cbStyle.TextColor, 2)
                    else
                      P.DrawGlyph(cbBoxRect, tgRadioDot, NodeStyle.TextColor, 2);
                  end;
                end;
              end; { case }
              Inc(captionX, cbSlotW);
            end;

            { Image (main column only) }
            usedImgSlotW := 0;
            if (FImages <> nil) and (FImages.Count > 0) then
            begin
              usedImgSlotW := imgSlotW;
              imgIdx  := -1;
              ghosted := False;
              if Assigned(FOnGetImageIndex) then
                FOnGetImageIndex(Self, node, ikNormal, colIdx, ghosted, imgIdx);
              { ③d D1: when this cell is owner-drawn the app owns the image too —
                do NOT collect it into pendingIcons (slot still reserved so the
                row width / chrome layout is unchanged). }
              if (not ownerDrawCell) and (imgIdx >= 0) and (imgIdx < FImages.Count) then
              begin
                { Collect; drawn via GDI onto ACanvas after EndPaint (see below). }
                if pendingCount = Length(pendingIcons) then
                  SetLength(pendingIcons, pendingCount + 32);
                pendingIcons[pendingCount].X   := ARect.Left + captionX;
                pendingIcons[pendingCount].Y   := ARect.Top  + rowTop + (rowH - FImages.Height) div 2;
                pendingIcons[pendingCount].Idx := imgIdx;
                Inc(pendingCount);
              end;
              Inc(captionX, imgSlotW);
            end;

            { Caption in main column — skipped for an owner-drawn cell (the app
              fully replaces the cell content via OnDrawNode post-EndPaint). }
            if not ownerDrawCell then
            begin
              colTxt := '';
              if Assigned(FOnGetTextWithType) then
                FOnGetTextWithType(Self, node, colIdx, ttNormal, colTxt)
              else if Assigned(FOnGetText) then
                FOnGetText(Self, node, colTxt);

              textRect := Rect(captionX + P.Scale(2), rowTop,
                               colCellRight - P.Scale(2), rowTop + rowH);
              if (textRect.Left < textRect.Right) and (colTxt <> '') then
                P.DrawText(textRect, colTxt,
                  NodeStyle.FontName, ResolveFontSize(NodeStyle), NodeStyle.FontWeight,
                  NodeStyle.TextColor, taLeftJustify, tlCenter, True);

              if Assigned(FOnPaintText) then
                FOnPaintText(Self, ACanvas, node, colIdx, ttNormal);
            end;
          end
          else
          begin
            { ── Non-main column: flat text cell ──────────────────────────── }
            { ③d D1: skipped for an owner-drawn cell (app fully replaces it). }
            if not ownerDrawCell then
            begin
              colMargin := P.Scale(4);
              colCaptionX := colCellLeft + colMargin;

              colTxt := '';
              if Assigned(FOnGetTextWithType) then
                FOnGetTextWithType(Self, node, colIdx, ttNormal, colTxt)
              else if Assigned(FOnGetText) then
                FOnGetText(Self, node, colTxt);   // fallback for compat

              colAlign := col.Alignment;
              textRect := Rect(colCaptionX, rowTop,
                               colCellRight - colMargin, rowTop + rowH);
              if (textRect.Left < textRect.Right) and (colTxt <> '') then
                P.DrawText(textRect, colTxt,
                  NodeStyle.FontName, ResolveFontSize(NodeStyle), NodeStyle.FontWeight,
                  NodeStyle.TextColor, colAlign, tlCenter, True);

              if Assigned(FOnPaintText) then
                FOnPaintText(Self, ACanvas, node, colIdx, ttNormal);
            end;
          end;

          { Restore clip to full inset rect after each cell }
          P.Bitmap.ClipRect := Rect(inset, inset, W - inset, H - inset);
        end;
        { FRangeX is already set from TotalWidth — do NOT re-accumulate }
      end
      else
      begin
        { ── ③a single-column path (0-column guard: verbatim ③a code) ───────── }

        { ③d A1: the ③a cell rect IS the content row rect; derive it from the
          SHARED helper so paint and GetCellRect(node, -1) agree exactly. This is
          purely additive (cellRect is not consumed by the verbatim chrome below
          in ③a; it backs ③d owner-draw). Equals Rect(CR.Left, rowTop, CR.Right,
          rowTop+rowH). }
        InternalCellRect(CR, rowTop, rowH, -1, APPI, cellRect);

        { ③d D1: 0-column owner-draw — Column = -1 (the whole row cell). Same
          collection as the multi-column paths; default caption/image skipped
          for the owner-drawn cell, row bg + chrome still paint underneath. }
        ownerDrawCell := ownerDrawActive;
        if ownerDrawCell then
        begin
          if pendingDrawCount = Length(pendingDrawNode) then
            SetLength(pendingDrawNode, pendingDrawCount + 32);
          pendingDrawNode[pendingDrawCount].Node := node;
          pendingDrawNode[pendingDrawCount].Col  := -1;
          pendingDrawNode[pendingDrawCount].R    := cellRect;
          Inc(pendingDrawCount);
        end;
        if Assigned(FOnAfterCellPaint) then
        begin
          if pendingAfterCount = Length(pendingAfter) then
            SetLength(pendingAfter, pendingAfterCount + 32);
          pendingAfter[pendingAfterCount].Node := node;
          pendingAfter[pendingAfterCount].Col  := -1;
          pendingAfter[pendingAfterCount].R    := cellRect;
          Inc(pendingAfterCount);
        end;

        { ── Tree lines (simplified: guide + elbow) ──────────────────────────── }
        if FShowTreeLines and (level > 0) then
        begin
          { Draw a vertical guide in each ancestor's column if that ancestor has
            a NextSibling (i.e. the guide continues past this row). }
          anc := node^.Parent;
          while (anc <> nil) and (anc <> FRoot) and (anc <> PTyTreeNode(Self)) do
          begin
            ancLevel := GetNodeLevel(anc);
            ancSlotX := contentLeft
                        + P.Scale((ancLevel + Ord(FShowRoot)) * FIndent)
                        - (btnSlotW shr 1);
            if anc^.NextSibling <> nil then
              P.Bitmap.DrawLine(ancSlotX, rowTop, ancSlotX, rowTop + rowH,
                TyColorToBGRA(S.BorderColor), False);
            anc := anc^.Parent;
          end;

          { Elbow at this node's level: vertical half + horizontal stub. }
          ancMidX := contentLeft
                     + P.Scale((level - 1 + Ord(FShowRoot)) * FIndent + FIndent)
                     - (btnSlotW shr 1);
          ancMidY := rowTop + rowH div 2;
          P.Bitmap.DrawLine(ancMidX, rowTop,    ancMidX, ancMidY,
            TyColorToBGRA(S.BorderColor), False);
          P.Bitmap.DrawLine(ancMidX, ancMidY,   contentLeft + indentPx, ancMidY,
            TyColorToBGRA(S.BorderColor), False);
          if node^.NextSibling <> nil then
            P.Bitmap.DrawLine(ancMidX, ancMidY, ancMidX, rowTop + rowH,
              TyColorToBGRA(S.BorderColor), False);
        end;

        { ── Expand button ────────────────────────────────────────────────── }
        if FShowButtons and (nsHasChildren in node^.States) then
        begin
          { The button occupies the slot just before indentPx. Use a CENTRED
            SQUARE filling the slot (side = min(slot, rowH)) so the chevron is
            large and crisp; DrawGlyph's pad is reduced to 2. }
          gSz := btnSlotW;
          if rowH < gSz then gSz := rowH;
          slotBaseX := contentLeft + indentPx - btnSlotW + (btnSlotW - gSz) div 2;
          btnRect := Rect(
            slotBaseX,
            rowTop + (rowH - gSz) div 2,
            slotBaseX + gSz,
            rowTop + (rowH - gSz) div 2 + gSz
          );
          if btnRect.Right  <= btnRect.Left  then btnRect.Right  := btnRect.Left  + 4;
          if btnRect.Bottom <= btnRect.Top   then btnRect.Bottom := btnRect.Top   + 4;
          if nsExpanded in node^.States then
            P.DrawGlyph(btnRect, tgChevronDown, NodeStyle.TextColor, P.Scale(1), 2)
          else
            P.DrawGlyph(btnRect, tgChevronRight, NodeStyle.TextColor, P.Scale(1), 2);
        end;

        { ── B2: Checkbox slot (after expand button, before image) ──────── }
        captionX := contentLeft + indentPx;
        usedCbSlotW := 0;
        if (toCheckSupport in FOptions) and (node^.CheckType <> ctNone) then
        begin
          cbSlotW     := P.Scale(16);
          usedCbSlotW := cbSlotW;
          { Resolve checkbox style }
          if node^.CheckState = csChecked then
            cbStyle := ActiveController.Model.ResolveStyle('TyTreeCheckBox', '', [tysActive])
          else if nsSelected in node^.States then
            cbStyle := ActiveController.Model.ResolveStyle('TyTreeCheckBox', '', [tysSelected])
          else
            cbStyle := ActiveController.Model.ResolveStyle('TyTreeCheckBox', '', []);
          cbBoxSize := P.Scale(12);
          if cbBoxSize > rowH - P.Scale(2) then cbBoxSize := rowH - P.Scale(2);
          if cbBoxSize < 4 then cbBoxSize := 4;
          cbBoxRect := Rect(
            captionX + (cbSlotW - cbBoxSize) div 2,
            rowTop + (rowH - cbBoxSize) div 2,
            captionX + (cbSlotW - cbBoxSize) div 2 + cbBoxSize,
            rowTop + (rowH - cbBoxSize) div 2 + cbBoxSize);
          { FIX 4: draw rectangular box background + border ONLY for checkbox
            types; ctRadioButton draws its own circle below (no square corners). }
          if node^.CheckType in [ctCheckBox, ctTriStateCheckBox] then
          begin
            if tpBackground in cbStyle.Present then
              P.FillBackground(cbBoxRect, cbStyle.Background, cbStyle.BorderRadius)
            else
              P.FillBackground(cbBoxRect, S.Background, 2);
            if tpBorderColor in cbStyle.Present then
              P.StrokeBorder(cbBoxRect, cbStyle.BorderRadius, cbStyle.BorderWidth, cbStyle.BorderColor)
            else
              P.StrokeBorder(cbBoxRect, 2, 1, S.BorderColor);
          end;
          { Glyph by CheckType + CheckState }
          case node^.CheckType of
            ctCheckBox, ctTriStateCheckBox:
            begin
              if node^.CheckState = csChecked then
              begin
                if tpTextColor in cbStyle.Present then
                  P.DrawGlyph(cbBoxRect, tgCheck, cbStyle.TextColor, 2)
                else
                  P.DrawGlyph(cbBoxRect, tgCheck, NodeStyle.TextColor, 2);
              end
              else if node^.CheckState = csMixed then
              begin
                if tpTextColor in cbStyle.Present then
                  P.Bitmap.FillRect(
                    cbBoxRect.Left + P.Scale(3), cbBoxRect.Top + P.Scale(3),
                    cbBoxRect.Right - P.Scale(3), cbBoxRect.Bottom - P.Scale(3),
                    TyColorToBGRA(cbStyle.TextColor))
                else
                  P.Bitmap.FillRect(
                    cbBoxRect.Left + P.Scale(3), cbBoxRect.Top + P.Scale(3),
                    cbBoxRect.Right - P.Scale(3), cbBoxRect.Bottom - P.Scale(3),
                    TyColorToBGRA(S.TextColor));
              end;
            end;
            ctRadioButton:
            begin
              { Draw circle only — no square box (FIX 4: prevents corner artifact) }
              if tpBackground in cbStyle.Present then
                P.FillBackground(cbBoxRect, cbStyle.Background, cbBoxSize div 2)
              else
                P.FillBackground(cbBoxRect, S.Background, cbBoxSize div 2);
              if tpBorderColor in cbStyle.Present then
                P.StrokeBorder(cbBoxRect, cbBoxSize div 2, cbStyle.BorderWidth, cbStyle.BorderColor)
              else
                P.StrokeBorder(cbBoxRect, cbBoxSize div 2, 1, S.BorderColor);
              if node^.CheckState = csChecked then
              begin
                if tpTextColor in cbStyle.Present then
                  P.DrawGlyph(cbBoxRect, tgRadioDot, cbStyle.TextColor, 2)
                else
                  P.DrawGlyph(cbBoxRect, tgRadioDot, NodeStyle.TextColor, 2);
              end;
            end;
          end; { case }
          Inc(captionX, cbSlotW);
        end;

        { ── Image ────────────────────────────────────────────────────────── }
        { The image slot is RESERVED whenever an image list is assigned (matching
          GetNodeAtPoint's hpImage zone), so usedImgSlotW mirrors that reservation
          for the FRangeX width below. }
        usedImgSlotW := 0;
        if (FImages <> nil) and (FImages.Count > 0) then
        begin
          usedImgSlotW := imgSlotW;
          imgIdx  := -1;
          ghosted := False;
          if Assigned(FOnGetImageIndex) then
            FOnGetImageIndex(Self, node, ikNormal, -1, ghosted, imgIdx);
          { ③d D1: owner-drawn cell owns its image — do not collect it. }
          if (not ownerDrawCell) and (imgIdx >= 0) and (imgIdx < FImages.Count) then
          begin
            { Collect; drawn via GDI onto ACanvas after EndPaint (see below). }
            if pendingCount = Length(pendingIcons) then
              SetLength(pendingIcons, pendingCount + 32);
            pendingIcons[pendingCount].X   := ARect.Left + captionX;
            pendingIcons[pendingCount].Y   := ARect.Top  + rowTop + (rowH - FImages.Height) div 2;
            pendingIcons[pendingCount].Idx := imgIdx;
            Inc(pendingCount);
          end;
          Inc(captionX, imgSlotW);
        end;

        { ── Caption ─────────────────────────────────────────────────────── }
        { ③d D1: skipped for an owner-drawn cell (app fully replaces it). }
        txt := '';
        if (not ownerDrawCell) and Assigned(FOnGetText) then
          FOnGetText(Self, node, txt);

        if not ownerDrawCell then
        begin
          textRect := Rect(captionX + P.Scale(2), rowTop, CR.Right, rowTop + rowH);
          if (textRect.Left < textRect.Right) and (txt <> '') then
            P.DrawText(textRect, txt,
              NodeStyle.FontName, ResolveFontSize(NodeStyle), NodeStyle.FontWeight,
              NodeStyle.TextColor, taLeftJustify, tlCenter, True);

          if Assigned(FOnPaintText) then
            FOnPaintText(Self, ACanvas, node, -1, ttNormal);
        end;

        { ── FRangeX accumulation ─────────────────────────────────────────── }
        { Pure content WIDTH for this row — independent of CR.Left and FOffsetX so
          the H-scroll range never drifts with the scroll position.  Equals the
          rendered layout: indent + cbSlot + (image slot if used) + gap + text + tail. }
        if txt <> '' then
        begin
          measW := indentPx + usedCbSlotW + usedImgSlotW + P.Scale(2) +
            P.MeasureText(txt, NodeStyle.FontName, ResolveFontSize(NodeStyle),
                          NodeStyle.FontWeight).cx + P.Scale(4);
          if measW > rangeXNew then
            rangeXNew := measW;
        end;
      end; { end ③a single-column path }

      node   := GetNextVisibleNoInit(node);
      Inc(rowTop, rowH);
    end;

    P.Bitmap.ClipRect := savedClip;
    P.EndPaint;

    { ── ③d D1 ── post-EndPaint owner-draw / icons / overlays ──────────────────
      EndPaint has alpha-blitted the BGRA layer onto ACanvas; ACanvas now holds
      the default-painted tree. ALL three of the following draw straight onto
      ACanvas via GDI — the ONLY path that survives every widgetset, because a
      GDI draw to ACanvas DURING RenderTo is erased by the EndPaint blit (the
      node-icon bug, commit d427095). The collected rects (.R) are painter-local
      (CR-space, 0-based); each clip is offset by ARect — and intersected with
      the content rect CR — exactly like the icon clip, so cells can't bleed over
      the header band or the border.

      Draw ORDER (matters): 1) OnDrawNode (replaced cell content, on the row bg)
      → 2) node images (existing; already skipped for owner-drawn cells) →
      3) OnAfterCellPaint (overlays, on top of everything). }

    { 1) OnDrawNode — full cell-content replacement (toOwnerDraw + handler). }
    if pendingDrawCount > 0 then
      for iCb := 0 to pendingDrawCount - 1 do
      begin
        savedDC := SaveDC(ACanvas.Handle);
        try
          IntersectClipRect(ACanvas.Handle,
            ARect.Left + CR.Left,  ARect.Top + CR.Top,
            ARect.Left + CR.Right, ARect.Top + CR.Bottom);
          IntersectClipRect(ACanvas.Handle,
            ARect.Left + pendingDrawNode[iCb].R.Left,  ARect.Top + pendingDrawNode[iCb].R.Top,
            ARect.Left + pendingDrawNode[iCb].R.Right, ARect.Top + pendingDrawNode[iCb].R.Bottom);
          FOnDrawNode(Self, ACanvas, pendingDrawNode[iCb].Node,
            pendingDrawNode[iCb].Col, pendingDrawNode[iCb].R);
        finally
          RestoreDC(ACanvas.Handle, savedDC);
        end;
      end;

    { 2) Node images: draw via GDI onto the (now composited) control canvas.
      Drawing into the BGRA layer's Canvas was erased by the EndPaint rebuild on
      Qt/GTK. The X/Y were captured in ARect-relative device coords (== ACanvas
      device coords here); CR is painter-local (0-based), so the clip is offset
      by ARect. Owner-drawn cells were already skipped at collection time. }
    if (pendingCount > 0) and (FImages <> nil) then
    begin
      savedDC := SaveDC(ACanvas.Handle);
      try
        IntersectClipRect(ACanvas.Handle,
          ARect.Left + CR.Left,  ARect.Top + CR.Top,
          ARect.Left + CR.Right, ARect.Top + CR.Bottom);
        for iIcon := 0 to pendingCount - 1 do
          FImages.Draw(ACanvas, pendingIcons[iIcon].X, pendingIcons[iIcon].Y,
            pendingIcons[iIcon].Idx);
      finally
        RestoreDC(ACanvas.Handle, savedDC);
      end;
    end;

    { 3) OnAfterCellPaint — overlay on top of default content + OnDrawNode. }
    if pendingAfterCount > 0 then
      for iCb := 0 to pendingAfterCount - 1 do
      begin
        savedDC := SaveDC(ACanvas.Handle);
        try
          IntersectClipRect(ACanvas.Handle,
            ARect.Left + CR.Left,  ARect.Top + CR.Top,
            ARect.Left + CR.Right, ARect.Top + CR.Bottom);
          IntersectClipRect(ACanvas.Handle,
            ARect.Left + pendingAfter[iCb].R.Left,  ARect.Top + pendingAfter[iCb].R.Top,
            ARect.Left + pendingAfter[iCb].R.Right, ARect.Top + pendingAfter[iCb].R.Bottom);
          FOnAfterCellPaint(Self, ACanvas, pendingAfter[iCb].Node,
            pendingAfter[iCb].Col, pendingAfter[iCb].R);
        finally
          RestoreDC(ACanvas.Handle, savedDC);
        end;
      end;
  finally
    P.Free;
  end;

  { After the loop: update the horizontal scrollbar if the widest row changed. }
  if rangeXNew <> FRangeX then
  begin
    FRangeX := rangeXNew;
    UpdateScrollBars;
  end;
end;

procedure TTyTreeView.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

{ ── C4 ── hit-testing + mouse + keyboard + hot-track ─────────────────────── }

{ GetNodeAtPoint (3-out overload)
  Convert client (X, Y) to the absolute content coordinate space, find the
  node under the cursor via GetNodeAt, then classify which column slot was hit.
  AColumn returns the collection Index of the column under X (-1 = NoColumn).

  X-accumulation mirrors RenderTo EXACTLY (same scale, same formula):
    CR      = ContentRect (padding-inset + scrollbar-shrunk, header inset already applied)
    indentPx = Scale((level + Ord(FShowRoot)) * FIndent)
    btnSlotW = Scale(FIndent)   — one Indent-wide slot before indentPx
    imgSlotW = Scale(FIndent)   — one Indent-wide slot after indentPx

  The absolute content X/Y:
    absY = (Y - CR.Top) + (-FOffsetY)
    absX = (X - CR.Left) + (-FOffsetX)  }
function TTyTreeView.GetNodeAtPoint(X, Y: Integer; out APart: TTyTreeHitPart; out AColumn: Integer): PTyTreeNode;
var
  PPI: Integer;
  CR: TRect;
  absY, absX: Integer;
  nodeTop: Integer;
  node: PTyTreeNode;
  level, indentPx, btnSlotW, imgSlotW: Integer;
  captionX: Integer;
  logX, logScroll: Integer;
begin
  Result   := nil;
  APart    := hpNowhere;
  AColumn  := NoColumn;

  PPI := Font.PixelsPerInch;
  CR  := ContentRect;

  { Convert to content-space coordinates.
    absY: (Y - CR.Top) is in device pixels; FOffsetY is logical.  Convert the
    device delta to logical before adding so both operands are in the same unit.
    absX: FOffsetX is device pixels (X axis is already device-consistent). }
  absY := MulDiv(Y - CR.Top, 96, PPI) + (-FOffsetY);
  absX := (X - CR.Left) + (-FOffsetX);

  if absY < 0 then Exit;

  node := GetNodeAt(absY, nodeTop);
  if node = nil then Exit;

  { Make sure the node is initialised so nsHasChildren is reliable }
  InitNode(node);

  { Compute the same x-zone layout as RenderTo }
  level    := GetNodeLevel(node);

  { Use a simple 1:1 scale helper: Scale(n) = MulDiv(n, PPI, 96) }
  indentPx := MulDiv((level + Ord(FShowRoot)) * FIndent, PPI, 96);
  btnSlotW := MulDiv(FIndent, PPI, 96);
  imgSlotW := MulDiv(FIndent, PPI, 96);

  { Zones (all in content-space X, i.e. relative to CR.Left after FOffsetX):
      [0 .. indentPx - btnSlotW)        = hpIndent (the left-padding area)
      [indentPx - btnSlotW .. indentPx) = hpButton slot (only when nsHasChildren)
      [indentPx .. indentPx + cbSlotW)  = hpCheckBox (B3: only when toCheckSupport + CheckType<>ctNone)
      [captionX .. captionX+imgSlotW)   = hpImage (only when FImages assigned)
      [captionX or beyond)              = hpLabel
    cbSlotW = MulDiv(16, PPI, 96) — identical to B2 paint formula.              }

  if absX < 0 then
  begin
    APart := hpIndent;
    Result := node;
  end
  else if absX < indentPx - btnSlotW then
  begin
    APart  := hpIndent;
    Result := node;
  end
  else if (absX < indentPx) then
  begin
    { In the button slot — classify as hpButton only if the node has children
      AND buttons are shown.  Otherwise treat as hpIndent. }
    if FShowButtons and (nsHasChildren in node^.States) then
      APart := hpButton
    else
      APart := hpIndent;
    Result := node;
  end
  else
  begin
    { Past the indent zone }
    captionX := indentPx;

    { B3: Checkbox slot — same width as B2 paint: MulDiv(16, PPI, 96) }
    if (toCheckSupport in FOptions) and (node^.CheckType <> ctNone) then
    begin
      if absX < captionX + MulDiv(16, PPI, 96) then
      begin
        APart  := hpCheckBox;
        Result := node;
        { Column detection happens below — don't Exit here }
      end
      else
      begin
        Inc(captionX, MulDiv(16, PPI, 96));
        if (FImages <> nil) and (FImages.Count > 0) then
        begin
          if absX < captionX + imgSlotW then
          begin
            APart  := hpImage;
            Result := node;
          end
          else
          begin
            Inc(captionX, imgSlotW);
            APart  := hpLabel;
            Result := node;
          end;
        end
        else
        begin
          APart  := hpLabel;
          Result := node;
        end;
      end;
    end
    else
    begin
      { No checkbox slot }
      if (FImages <> nil) and (FImages.Count > 0) then
      begin
        if absX < captionX + imgSlotW then
        begin
          APart  := hpImage;
          Result := node;
        end
        else
        begin
          Inc(captionX, imgSlotW);
          APart  := hpLabel;
          Result := node;
        end;
      end
      else
      begin
        { Everything to the right of the indent zone is the label area }
        APart  := hpLabel;
        Result := node;
      end;
    end;
  end;

  { D1: determine which column the X coordinate lands in (when columns exist) }
  if (Result <> nil) and (FHeader <> nil) and (FHeader.Columns.Count > 0) then
  begin
    { Convert device X offset from CR.Left into logical px (matches paint formula).
      ColumnFromPosition(logX, logScroll) checks col.FLeft-logScroll <= logX < col.FLeft-logScroll+col.Width
      which matches CR.Left + Scale(col.Left) + FOffsetX <= X < ... }
    logX      := MulDiv(X - CR.Left, 96, PPI);
    logScroll := MulDiv(-FOffsetX, 96, PPI);
    AColumn := FHeader.Columns.ColumnFromPosition(logX, logScroll);
  end;
end;

{ GetNodeAtPoint (2-out overload — backward-compatible delegator) }
function TTyTreeView.GetNodeAtPoint(X, Y: Integer; out APart: TTyTreeHitPart): PTyTreeNode;
var
  col: Integer;
begin
  Result := GetNodeAtPoint(X, Y, APart, col);
end;

{ GetHeaderHitAt
  Returns True and sets APart + AColumn when (X,Y) is inside the header band.
  The header band occupies device Y in [CR.Top-headerH .. CR.Top) where
  CR = ContentRect (which already has headerH added to its Top). }
function TTyTreeView.GetHeaderHitAt(X, Y: Integer; out APart: TTyTreeHitPart; out AColumn: Integer): Boolean;
var
  PPI, logX, logScroll, colIdx: Integer;
  CR: TRect;
begin
  Result  := False;
  APart   := hpNowhere;
  AColumn := NoColumn;

  { Guard: header must be present, visible, and have at least one column }
  if (FHeader = nil) or not (hoVisible in FHeader.Options) or
     (FHeader.Columns.Count = 0) then Exit;

  CR := ContentRect;
  { ContentRect.Top already includes the header band height.
    Any Y below ContentRect.Top is in the header/padding band.
    Check both the upper boundary (Y >= padding top = CR.Top - headerH) and lower
    boundary (Y < CR.Top).  We use Y < CR.Top as the sufficient test — clicking
    in the narrow padding above the header is treated as a header hit. }
  if Y >= CR.Top then Exit;

  { We're in the header band }
  PPI := Font.PixelsPerInch;

  { Compute logical X relative to CR.Left (shared horizontal geometry with cells).
    ColumnFromPosition and DetermineSplitterIndex both use the same paint formula. }
  logX      := MulDiv(X - CR.Left, 96, PPI);
  logScroll := MulDiv(-FOffsetX, 96, PPI);

  { Check for divider (resizable column right-edge within tolerance) — only when
    column resize is enabled; otherwise the divider zone belongs to the clickable
    (sortable) header section so a click near a border still sorts. }
  colIdx := NoColumn;
  if hoColumnResize in FHeader.Options then
    colIdx := FHeader.Columns.DetermineSplitterIndex(logX, logScroll);
  if colIdx <> NoColumn then
  begin
    APart   := hpHeaderDivider;
    AColumn := colIdx;
    Result  := True;
  end
  else
  begin
    { Plain header section hit }
    AColumn := FHeader.Columns.ColumnFromPosition(logX, logScroll);
    APart   := hpHeaderSection;
    Result  := True;
  end;
end;

procedure TTyTreeView.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  part: TTyTreeHitPart;
  node: PTyTreeNode;
  headerPart: TTyTreeHitPart;
  headerCol: Integer;
  col: TTyTreeColumn;
  col2: Integer;   { E3: column under the cursor (out param of the hit-test) }
begin
  inherited MouseDown(Button, Shift, X, Y);

  if not Enabled then Exit;

  { Request keyboard focus so arrow-key navigation works after click }
  if CanSetFocus then SetFocus;

  { D2: header hit test — intercept before node hit-test }
  if GetHeaderHitAt(X, Y, headerPart, headerCol) then
  begin
    if (Button = mbLeft) and (headerPart = hpHeaderDivider) and
       (headerCol <> NoColumn) and
       (hoColumnResize in FHeader.Options) then
    begin
      col := FHeader.Columns.Items[headerCol] as TTyTreeColumn;
      FResizeColumn     := headerCol;
      FResizeStartWidth := col.Width;
      FResizeStartX     := X;
      { D2 fix: guard against handle allocation in headless tests }
      if HandleAllocated then MouseCapture := True;
    end
    else if (Button = mbLeft) and (headerPart = hpHeaderSection) and
            (headerCol <> NoColumn) then
    begin
      { Record a header-section press. A plain press+release sorts on MouseUp
        (E3 header-click); a drag-reorder only ENGAGES in MouseMove when
        hoDrag + coDraggable allow it — so header-click sort works even when
        drag-reorder is disabled (decoupled from hoDrag/coDraggable). }
      col := FHeader.Columns.Items[headerCol] as TTyTreeColumn;
      FDragColumn    := headerCol;
      FDragPending   := True;
      FDragStartX    := X;
      FDragging      := False;
      FDragTargetPos := col.Position;
      if HandleAllocated then MouseCapture := True;
    end;
    Exit;  { don't fall through to node hit-test when in header }
  end;

  node := GetNodeAtPoint(X, Y, part, col2);
  FLastMouseNode    := node;
  { E3: record the column + hit part for the edit triggers. FLastMouseColumn is
    the column under the cursor (NoColumn when 0 columns / outside any cell); F2
    uses it. FLastMouseHitPart lets DblClick distinguish an editable cell region
    (hpLabel/hpImage) from the expand button / checkbox. }
  FLastMouseColumn  := col2;
  FLastMouseHitPart := part;

  if Button = mbLeft then
  begin
    if node = nil then Exit;

    if part = hpButton then
    begin
      { Click on the expand/collapse button — toggle, do NOT change selection }
      Expanded[node] := not Expanded[node];
    end
    else if part = hpCheckBox then
    begin
      { C1: click on the checkbox slot — toggle the check state, do NOT change
        selection or focus (a checkbox click is purely a check operation). }
      ToggleCheck(node);
    end
    else
    begin
      { Click on any other part (label, image, indent) — select/focus the node.
        D1: when toMultiSelect, apply Ctrl/Shift modifier semantics.
        D2: when toFullRowSelect, any in-row part (already in this branch) is
            treated as a selection hit.  Without toFullRowSelect, only the
            main-column content zones (label/image) are taken as selection hits;
            hpIndent still reaches here, but without toFullRowSelect we only
            count it as a selection gesture if it's hpLabel or hpImage.
            Note: hpButton and hpCheckBox are already handled above; this branch
            covers hpLabel, hpImage, hpIndent (and any future column parts). }
      if toMultiSelect in FOptions then
      begin
        { Determine whether this part counts as a selectable hit }
        if (toFullRowSelect in FOptions) or (part in [hpLabel, hpImage]) then
        begin
          { Multi-select modifier matrix }
          if (ssShift in Shift) and (ssCtrl in Shift) then
          begin
            { Ctrl+Shift: extend range on top of existing selection (no clear) }
            if FRangeAnchor = nil then FRangeAnchor := node;
            AddRangeToSelection(FRangeAnchor, node);
            MoveFocusOnly(node);
            if Assigned(FOnSelectionChanged) then FOnSelectionChanged(Self);
          end
          else if ssShift in Shift then
          begin
            { Shift: select range from anchor to node; anchor unchanged }
            if FRangeAnchor = nil then FRangeAnchor := node;
            SelectRange(FRangeAnchor, node);
            MoveFocusOnly(node);
            if Assigned(FOnSelectionChanged) then FOnSelectionChanged(Self);
          end
          else if ssCtrl in Shift then
          begin
            { Ctrl: toggle membership; update anchor; no clear }
            InternalSetSelected(node, not (nsSelected in node^.States));
            FRangeAnchor := node;
            MoveFocusOnly(node);
            if Assigned(FOnSelectionChanged) then FOnSelectionChanged(Self);
          end
          else
          begin
            { Plain click: clear selection, select one, reset anchor }
            ClearSelection;
            InternalSetSelected(node, True);
            FRangeAnchor := node;
            MoveFocusOnly(node);
            if Assigned(FOnSelectionChanged) then FOnSelectionChanged(Self);
          end;
          Invalidate;
          if Assigned(FOnNodeClick) then FOnNodeClick(Self, node);
        end
        else
        begin
          { Indent-only click without toFullRowSelect — treat as focus/select (③b) }
          FocusedNode := node;
          if Assigned(FOnNodeClick) then FOnNodeClick(Self, node);
        end;
      end
      else
      begin
        { Single-select path (③a/③b): unchanged behaviour }
        FocusedNode := node;
        if Assigned(FOnNodeClick) then FOnNodeClick(Self, node);
      end;
    end;
  end
  else if Button = mbRight then
  begin
    { Right-click: always move focus to the clicked node (mirrors VTV right-down
      behaviour).  Doing this unconditionally avoids a desync where FocusedNode
      and the visually-highlighted row differ when the node was programmatically
      selected without focus, and keeps keyboard nav anchored to the right row. }
    if node <> nil then
      FocusedNode := node;
  end;
end;

procedure TTyTreeView.DblClick;
var
  node: PTyTreeNode;
  editCol: Integer;
begin
  inherited DblClick;
  { FLastMouseNode was set by the preceding MouseDown; use it here so we don't
    need to re-probe the mouse position (which may have drifted). }
  node := FLastMouseNode;
  if node = nil then Exit;

  { ③e E3: double-click-to-edit takes precedence over expand-toggle, but ONLY on
    the LABEL region — never the expand button, the checkbox, OR the icon (each
    has its own gesture). When the press landed on the label and EditNode
    succeeds, consume the double-click (skip the toggle + OnNodeDblClick) so
    editable cells edit instead of toggling. Otherwise fall through to the
    existing behaviour UNCHANGED (so Options=[] / non-editable cells are
    byte-identical). FIX 7 (adversarial): hpImage dropped — double-clicking the
    icon now falls through to the toggle, matching VirtualTreeView. The effective
    column is FLastMouseColumn when it names a real column, else MainColumn
    (EditNode resolves NoColumn → MainColumn internally). }
  if (toEditable in FOptions) and not FEditing and
     (FLastMouseHitPart in [hpLabel]) then
  begin
    if FLastMouseColumn <> NoColumn then editCol := FLastMouseColumn
    else                                 editCol := FHeader.MainColumn;
    if EditNode(node, editCol) then Exit;
  end;

  { ToggleOnDblClick: toggle expand/collapse on the node (only if expandable
    and the click was NOT on the explicit button — that already toggled on Down). }
  if FToggleOnDblClick and (nsHasChildren in node^.States) then
    Expanded[node] := not Expanded[node];

  if Assigned(FOnNodeDblClick) then FOnNodeDblClick(Self, node);
end;

procedure TTyTreeView.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  part: TTyTreeHitPart;
  node: PTyTreeNode;
  hPart: TTyTreeHitPart;
  hCol, PPI, newWidth: Integer;
  col: TTyTreeColumn;
  threshold, logX, logScroll, hitColIdx, targetPos: Integer;
begin
  hitColIdx := NoColumn;
  targetPos := 0;
  inherited MouseMove(Shift, X, Y);

  { D2: active column resize drag }
  if FResizeColumn <> NoColumn then
  begin
    PPI := Font.PixelsPerInch;
    newWidth := FResizeStartWidth + MulDiv(X - FResizeStartX, 96, PPI);
    col := FHeader.Columns.Items[FResizeColumn] as TTyTreeColumn;
    col.Width := newWidth;  // setter clamps + UpdatePositions + fires HeaderChanged → repaint
    if Assigned(FOnColumnResized) then
      FOnColumnResized(Self, FResizeColumn);
    { D4: if hoAutoResize is on, re-apply auto-size after a manual resize }
    if (hoAutoResize in FHeader.Options) and (FHeader.AutoSizeIndex >= 0) and
       (FHeader.AutoSizeIndex < FHeader.Columns.Count) then
    begin
      PPI := Font.PixelsPerInch;
      FHeader.Columns.ApplyAutoSize(
        MulDiv(ContentRect.Width, 96, PPI),
        FHeader.AutoSizeIndex);
      if FHeader.Columns.Count > 0 then
        FRangeX := MulDiv(FHeader.Columns.TotalWidth, Font.PixelsPerInch, 96);
      UpdateScrollBars;
    end;
    Exit;
  end;

  { D3: active or pending column drag-reorder }
  if FDragPending or FDragging then
  begin
    threshold := MulDiv(4, Font.PixelsPerInch, 96);
    if not FDragging and (Abs(X - FDragStartX) > threshold) and
       (hoDrag in FHeader.Options) and
       (FDragColumn >= 0) and (FDragColumn < FHeader.Columns.Count) and
       (coDraggable in (FHeader.Columns.Items[FDragColumn] as TTyTreeColumn).Options) then
    begin
      FDragging := True;
      Invalidate;
    end;

    if FDragging then
    begin
      { Compute the target visual position from the current X }
      PPI       := Font.PixelsPerInch;
      logX      := MulDiv(X - ContentRect.Left, 96, PPI);
      logScroll := MulDiv(-FOffsetX, 96, PPI);
      hitColIdx := FHeader.Columns.ColumnFromPosition(logX, logScroll);

      if hitColIdx <> NoColumn then
      begin
        col := FHeader.Columns.Items[hitColIdx] as TTyTreeColumn;
        targetPos := col.Position;
      end
      else
      begin
        { X is past the last column — clamp to the last visible position }
        targetPos := FHeader.Columns.Count - 1;
      end;

      if targetPos < 0 then targetPos := 0;
      if targetPos > FHeader.Columns.Count - 1 then
        targetPos := FHeader.Columns.Count - 1;

      if targetPos <> FDragTargetPos then
      begin
        FDragTargetPos := targetPos;
        Invalidate;
      end
      else
        Invalidate;  { always repaint to update ghost position }
    end;
    Exit;
  end;

  { D2: cursor feedback for header divider hover }
  if (FHeader <> nil) and (FHeader.Columns.Count > 0) and
     (hoColumnResize in FHeader.Options) then
  begin
    hPart := hpNowhere;
    hCol  := NoColumn;
    if GetHeaderHitAt(X, Y, hPart, hCol) and (hPart = hpHeaderDivider) then
      Cursor := crHSplit
    else
      Cursor := crDefault;
  end;

  if not FHotTrack then Exit;

  node := GetNodeAtPoint(X, Y, part);
  if node <> FHotNode then
  begin
    FHotNode := node;
    Invalidate;
  end;

end;

procedure TTyTreeView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  draggedCol: TTyTreeColumn;
  oldPos, newPos: Integer;
begin
  inherited MouseUp(Button, Shift, X, Y);

  if (Button = mbLeft) and (FResizeColumn <> NoColumn) then
  begin
    if Assigned(FOnColumnResized) then
      FOnColumnResized(Self, FResizeColumn);
    FResizeColumn := NoColumn;
    if HandleAllocated then MouseCapture := False;
  end;

  { D3: end of drag-reorder }
  if (Button = mbLeft) and (FDragPending or FDragging) then
  begin
    if FDragging and (FDragColumn <> NoColumn) then
    begin
      draggedCol := FHeader.Columns.Items[FDragColumn] as TTyTreeColumn;
      oldPos := draggedCol.Position;
      newPos := FDragTargetPos;
      if newPos <> Integer(oldPos) then
      begin
        FHeader.Columns.AdjustPosition(draggedCol, newPos);
        { AdjustPosition already calls UpdatePositions + DoChange → HeaderChanged }
        if Assigned(FOnColumnReorder) then
          FOnColumnReorder(Self, oldPos, newPos);
      end;
    end
    else if FDragPending and not FDragging and (FDragColumn <> NoColumn) then
    begin
      { E3: plain press+release (no drag) on a header section = header click }
      _HandleHeaderClick(FDragColumn);
    end;
    { Clear drag state }
    FDragColumn    := NoColumn;
    FDragPending   := False;
    FDragging      := False;
    FDragTargetPos := 0;
    if HandleAllocated then MouseCapture := False;
    Invalidate;
  end;
end;

procedure TTyTreeView.MouseLeave;
begin
  inherited MouseLeave;
  if FHotNode <> nil then
  begin
    FHotNode := nil;
    Invalidate;
  end;
end;

procedure TTyTreeView.KeyDown(var Key: Word; Shift: TShiftState);
var
  cur, nxt: PTyTreeNode;
  viewH, rowH, pgRows, i: Integer;
  colIdx: Integer;   { E3: effective edit column for F2 }
begin
  inherited KeyDown(Key, Shift);

  cur := FFocusedNode;

  { ③d C1: Backspace pops the last char of an active incremental-search buffer
    and re-runs the search. Multibyte-safe (UTF8Copy/UTF8Length, not Delete(.,Length,1)).
    Only intercepts while actually searching (buffer non-empty) so plain trees keep
    Backspace untouched; suppressed while an editor is active (FEditing, ③e). }
  if (toIncrementalSearch in FOptions) and not FEditing
     and (FSearchBuffer <> '') and (Key = VK_BACK) then
  begin
    FSearchBuffer   := UTF8Copy(FSearchBuffer, 1, UTF8Length(FSearchBuffer) - 1);
    FSearchLastTick := GetTickCount64;
    DoIncrementalSearch;   // re-resolve focus against the shortened buffer (no-op when empty)
    Key := 0;
    Exit;
  end;

  { D2: multi-select keyboard overrides for Shift+arrows, Ctrl+Space, Ctrl+A.
    These are checked BEFORE the main case so they can intercept VK_DOWN/VK_UP. }
  if toMultiSelect in FOptions then
  begin
    { Ctrl+A — select all visible nodes }
    if (ssCtrl in Shift) and (Key = Ord('A')) then
    begin
      SelectAll;
      Key := 0;
      Exit;
    end;

    { Ctrl+Space — toggle selection on the focused node }
    if (ssCtrl in Shift) and (Key = VK_SPACE) then
    begin
      if cur <> nil then
      begin
        InternalSetSelected(cur, not (nsSelected in cur^.States));
        Invalidate;
        if Assigned(FOnSelectionChanged) then FOnSelectionChanged(Self);
      end;
      Key := 0;
      Exit;
    end;

    { Shift+Down — move caret down and extend range from anchor to caret }
    if (ssShift in Shift) and (Key = VK_DOWN) then
    begin
      if cur = nil then
        nxt := GetFirstVisibleNoInit
      else
        nxt := GetNextVisibleNoInit(cur);
      if nxt <> nil then
      begin
        if FRangeAnchor = nil then FRangeAnchor := cur;
        MoveFocusOnly(nxt);
        SelectRange(FRangeAnchor, nxt);
        ScrollIntoView(nxt);
        if Assigned(FOnSelectionChanged) then FOnSelectionChanged(Self);
      end;
      Key := 0;
      Exit;
    end;

    { Shift+Up — move caret up and extend range from anchor to caret }
    if (ssShift in Shift) and (Key = VK_UP) then
    begin
      if cur <> nil then
      begin
        nxt := GetPreviousVisibleNoInit(cur);
        if nxt <> nil then
        begin
          if FRangeAnchor = nil then FRangeAnchor := cur;
          MoveFocusOnly(nxt);
          SelectRange(FRangeAnchor, nxt);
          ScrollIntoView(nxt);
          if Assigned(FOnSelectionChanged) then FOnSelectionChanged(Self);
        end;
      end;
      Key := 0;
      Exit;
    end;
  end;

  case Key of

    VK_DOWN:
    begin
      if cur = nil then
        nxt := GetFirstVisibleNoInit
      else
        nxt := GetNextVisibleNoInit(cur);
      if nxt <> nil then
      begin
        if toMultiSelect in FOptions then
        begin
          { Plain Down in multi-select: collapse to single selection + reset anchor }
          ClearSelection;
          InternalSetSelected(nxt, True);
          FRangeAnchor := nxt;
          MoveFocusOnly(nxt);
          Invalidate;
          if Assigned(FOnSelectionChanged) then FOnSelectionChanged(Self);
          ScrollIntoView(nxt);
        end
        else
        begin
          FocusedNode := nxt;
          ScrollIntoView(nxt);
        end;
      end;
      Key := 0;
    end;

    VK_UP:
    begin
      if cur <> nil then
      begin
        nxt := GetPreviousVisibleNoInit(cur);
        if nxt <> nil then
        begin
          if toMultiSelect in FOptions then
          begin
            { Plain Up in multi-select: collapse to single selection + reset anchor }
            ClearSelection;
            InternalSetSelected(nxt, True);
            FRangeAnchor := nxt;
            MoveFocusOnly(nxt);
            Invalidate;
            if Assigned(FOnSelectionChanged) then FOnSelectionChanged(Self);
            ScrollIntoView(nxt);
          end
          else
          begin
            FocusedNode := nxt;
            ScrollIntoView(nxt);
          end;
        end;
      end;
      Key := 0;
    end;

    VK_RIGHT:
    begin
      if cur <> nil then
      begin
        InitNode(cur);
        if (nsHasChildren in cur^.States) and not (nsExpanded in cur^.States) then
          Expanded[cur] := True          // expand collapsed node
        else
        begin
          { Already expanded or no children: move to first child }
          nxt := GetNextVisibleNoInit(cur);
          if (nxt <> nil) and (nxt^.Parent = cur) then
          begin
            FocusedNode := nxt;
            ScrollIntoView(nxt);
          end;
        end;
      end;
      Key := 0;
    end;

    VK_LEFT:
    begin
      if cur <> nil then
      begin
        if nsExpanded in cur^.States then
          Expanded[cur] := False         // collapse expanded node
        else
        begin
          { Move to parent (if not root-level) }
          nxt := GetParent(cur);
          if nxt <> nil then
          begin
            FocusedNode := nxt;
            ScrollIntoView(nxt);
          end;
        end;
      end;
      Key := 0;
    end;

    VK_HOME:
    begin
      nxt := GetFirstVisibleNoInit;
      if nxt <> nil then
      begin
        if toMultiSelect in FOptions then
        begin
          ClearSelection;
          InternalSetSelected(nxt, True);
          FRangeAnchor := nxt;
          MoveFocusOnly(nxt);
          Invalidate;
          if Assigned(FOnSelectionChanged) then FOnSelectionChanged(Self);
          ScrollIntoView(nxt);
        end
        else
        begin
          FocusedNode := nxt;
          ScrollIntoView(nxt);
        end;
      end;
      Key := 0;
    end;

    VK_END:
    begin
      { Walk to the last visible node }
      nxt := GetFirstVisibleNoInit;
      if nxt <> nil then
      begin
        while GetNextVisibleNoInit(nxt) <> nil do
          nxt := GetNextVisibleNoInit(nxt);
        if toMultiSelect in FOptions then
        begin
          ClearSelection;
          InternalSetSelected(nxt, True);
          FRangeAnchor := nxt;
          MoveFocusOnly(nxt);
          Invalidate;
          if Assigned(FOnSelectionChanged) then FOnSelectionChanged(Self);
          ScrollIntoView(nxt);
        end
        else
        begin
          FocusedNode := nxt;
          ScrollIntoView(nxt);
        end;
      end;
      Key := 0;
    end;

    VK_PRIOR:  { Page Up }
    begin
      if cur <> nil then
      begin
        { ③d B1: page estimate uses FDefaultNodeHeight even with variable
          heights — acceptable approximation (ScrollIntoView corrects the view). }
        rowH  := MulDiv(FDefaultNodeHeight, Font.PixelsPerInch, 96);
        viewH := ContentRect.Bottom - ContentRect.Top;
        if rowH > 0 then pgRows := viewH div rowH else pgRows := 1;
        if pgRows < 1 then pgRows := 1;
        nxt := cur;
        for i := 1 to pgRows do
        begin
          if GetPreviousVisibleNoInit(nxt) <> nil then
            nxt := GetPreviousVisibleNoInit(nxt)
          else
            Break;
        end;
        FocusedNode := nxt;
        ScrollIntoView(nxt);
      end;
      Key := 0;
    end;

    VK_NEXT:   { Page Down }
    begin
      if cur = nil then cur := GetFirstVisibleNoInit;
      if cur <> nil then
      begin
        rowH  := MulDiv(FDefaultNodeHeight, Font.PixelsPerInch, 96);
        viewH := ContentRect.Bottom - ContentRect.Top;
        if rowH > 0 then pgRows := viewH div rowH else pgRows := 1;
        if pgRows < 1 then pgRows := 1;
        nxt := cur;
        for i := 1 to pgRows do
        begin
          if GetNextVisibleNoInit(nxt) <> nil then
            nxt := GetNextVisibleNoInit(nxt)
          else
            Break;
        end;
        FocusedNode := nxt;
        ScrollIntoView(nxt);
      end;
      Key := 0;
    end;

    VK_ADD, Ord('+'):   { Expand }
    begin
      if cur <> nil then
      begin
        InitNode(cur);
        if nsHasChildren in cur^.States then
          Expanded[cur] := True;
      end;
      Key := 0;
    end;

    VK_SUBTRACT, Ord('-'):  { Collapse }
    begin
      if cur <> nil then
        Expanded[cur] := False;
      Key := 0;
    end;

    VK_MULTIPLY, Ord('*'):   { FullExpand from focused node }
    begin
      if cur <> nil then
        FullExpand(cur)
      else
        FullExpand(nil);
      Key := 0;
    end;

    VK_RETURN:
    begin
      if (cur <> nil) and Assigned(FOnNodeDblClick) then
        FOnNodeDblClick(Self, cur);
      Key := 0;
    end;

    VK_F2:
    begin
      { ③e E3: F2 starts editing the focused node. Gated on toEditable + a focused
        node + not already editing, so non-editable trees leave F2 untouched (the
        key is only consumed when an edit actually starts). Effective column:
        FLastMouseColumn when it names a real column, else MainColumn if valid,
        else 0 (single-column / 0-column trees). }
      if (toEditable in FOptions) and (cur <> nil) and not FEditing then
      begin
        if (FLastMouseColumn >= 0) and
           (FHeader <> nil) and (FLastMouseColumn < FHeader.Columns.Count) then
          colIdx := FLastMouseColumn
        else if (FHeader <> nil) and (FHeader.MainColumn >= 0) and
                (FHeader.MainColumn < FHeader.Columns.Count) then
          colIdx := FHeader.MainColumn
        else
          colIdx := 0;
        EditNode(cur, colIdx);
        Key := 0;
      end;
    end;

    VK_SPACE:
    begin
      { C1: Space toggles the check state of the focused node when toCheckSupport
        is active and the node has a non-None CheckType.  Falls through (key NOT
        consumed) when the tree has no check support so that non-check trees are
        unaffected.
        D2: Ctrl+Space (for multi-select toggle) is handled above; plain Space
        here only triggers check-toggle, NOT selection-toggle. }
      if (toCheckSupport in FOptions) and
         (cur <> nil) and (cur^.CheckType <> ctNone) then
      begin
        ToggleCheck(cur);
        Key := 0;
      end;
    end;

  end;
end;

{ ── ③d C1 ── UTF8KeyPress: type-to-find ───────────────────────────────────── }

{ LCL delivers printable characters here (its WM_CHAR equivalent), AFTER KeyDown.
  We call inherited first (so OnUTF8KeyPress / normal handling runs), then — when
  toIncrementalSearch is on and no editor is active and the char is printable —
  accumulate it into FSearchBuffer (resetting first if the idle timeout elapsed)
  and jump focus to the matching visible node (see DoIncrementalSearch for the
  start-position rule: re-pressing one char advances, refining keeps focus). }
procedure TTyTreeView.UTF8KeyPress(var UTF8Key: TUTF8Char);
begin
  inherited UTF8KeyPress(UTF8Key);

  if not (toIncrementalSearch in FOptions) then Exit;
  if FEditing then Exit;
  { Printable only: non-empty and the first byte is >= space (filters control
    chars — Backspace/Tab/Enter arrive as #8/#9/#13 and are handled in KeyDown). }
  if (UTF8Key = '') or (UTF8Key[1] < #32) then Exit;

  { Idle longer than SearchTimeout ⇒ start a fresh search. }
  if GetTickCount64 - FSearchLastTick > QWord(FSearchTimeout) then
    FSearchBuffer := '';
  FSearchBuffer   := FSearchBuffer + UTF8Key;
  FSearchLastTick := GetTickCount64;

  DoIncrementalSearch;
end;

{ ── E1 ── sort engine ────────────────────────────────────────────────────── }

{ DoCompare: wraps OnCompareNodes.  Returns 0 when no handler assigned.
  The caller uses natural ordering; the sort direction is handled by the merge. }
function TTyTreeView.DoCompare(Node1, Node2: PTyTreeNode; Column: Integer): Integer;
begin
  Result := 0;
  if Assigned(FOnCompareNodes) then
    FOnCompareNodes(Self, Node1, Node2, Column, Result);
end;

{ MergeSortedLists: merge two sorted singly-linked (NextSibling) lists into one.
  AscDir = True  → pick the SMALLER node first (ascending)
  AscDir = False → pick the LARGER  node first (descending)
  Only NextSibling is used during the merge; PrevSibling/Index/Parent are
  repaired by the sweep in Sort after this returns. }
function MergeSortedLists(Tree: TTyTreeView; A, B: PTyTreeNode;
  Column: Integer; AscDir: Boolean): PTyTreeNode;
var
  head, tail, chosen: PTyTreeNode;
  cmp: Integer;
begin
  head := nil;
  tail := nil;
  while (A <> nil) and (B <> nil) do
  begin
    cmp := Tree.DoCompare(A, B, Column);
    { Ascending: pick A when cmp <= 0 (stable: equal stays in original order).
      Descending: pick A when cmp >= 0. }
    if AscDir then
    begin
      if cmp <= 0 then chosen := A else chosen := B;
    end
    else
    begin
      if cmp >= 0 then chosen := A else chosen := B;
    end;
    if chosen = A then A := A^.NextSibling
    else              B := B^.NextSibling;
    chosen^.NextSibling := nil;  { isolate the node }
    if tail = nil then begin head := chosen; tail := chosen; end
    else begin tail^.NextSibling := chosen; tail := chosen; end;
  end;
  { Append whichever list still has nodes }
  if tail <> nil then
  begin
    if A <> nil then tail^.NextSibling := A
    else             tail^.NextSibling := B;
  end;
  if head = nil then
  begin
    if A <> nil then Result := A
    else              Result := B;
  end
  else Result := head;
end;

{ MergeSortList: top-down recursive merge sort on a singly-linked list
  (linked via NextSibling only).  Returns the new head of the sorted list.
  ACount = number of nodes in the list (for efficient split). }
function MergeSortList(Tree: TTyTreeView; Head: PTyTreeNode;
  ACount: Integer; Column: Integer; AscDir: Boolean): PTyTreeNode;
var
  half, i: Integer;
  slow, fast, left, right: PTyTreeNode;
begin
  if (Head = nil) or (ACount <= 1) then begin Result := Head; Exit; end;

  { Split: advance by ACount div 2 nodes to find the midpoint }
  half := ACount div 2;
  slow := Head;
  for i := 1 to half - 1 do
    slow := slow^.NextSibling;
  fast  := slow^.NextSibling;   { second half starts here }
  slow^.NextSibling := nil;      { cut the list }
  left  := Head;
  right := fast;

  left  := MergeSortList(Tree, left,  half,         Column, AscDir);
  right := MergeSortList(Tree, right, ACount - half, Column, AscDir);

  Result := MergeSortedLists(Tree, left, right, Column, AscDir);
end;

{ Sort: sort the direct children of Node one level.
  DoInit=True → lazily materialise children first (matches the ③a lazy model). }
procedure TTyTreeView.Sort(Node: PTyTreeNode; Column: Integer;
  ADirection: TTySortDirection; DoInit: Boolean);
var
  child, prev: PTyTreeNode;
  newHead: PTyTreeNode;
  idx: Cardinal;
  cnt: Integer;
begin
  if Node = nil then Exit;

  { Step 1: if DoInit, ensure children are materialised and each child is inited }
  if DoInit then
  begin
    if (nsHasChildren in Node^.States) and (Node^.ChildCount = 0) then
      InitChildren(Node);
    { Init each direct child so nsHasChildren etc. are populated for compare }
    child := Node^.FirstChild;
    while child <> nil do
    begin
      InitNode(child);
      child := child^.NextSibling;
    end;
  end;

  cnt := Node^.ChildCount;
  if cnt <= 1 then Exit;   { 0 or 1 child: nothing to sort }

  { Step 2: merge sort the FirstChild→NextSibling singly-linked list }
  newHead := MergeSortList(Self, Node^.FirstChild, cnt, Column,
                           ADirection = sdAscending);

  { Step 3: sweep the sorted list to rebuild full doubly-linked structure
    and re-stamp Index. }
  Node^.FirstChild := newHead;
  prev := nil;
  idx  := 0;
  child := newHead;
  while child <> nil do
  begin
    child^.Parent      := Node;
    child^.Index       := idx;
    child^.PrevSibling := prev;
    if prev <> nil then
      prev^.NextSibling := child;
    prev := child;
    child := child^.NextSibling;
    Inc(idx);
  end;
  { prev is now the last node }
  if prev <> nil then
  begin
    prev^.NextSibling := nil;
    Node^.LastChild   := prev;
  end;
  { ChildCount/TotalCount/TotalHeight are unchanged (same set of children) }
end;

{ ── E3 ── header-click sort wiring ──────────────────────────────────────── }

{ _HandleHeaderClick: called from MouseUp when a header section receives a
  plain click (press+release with no drag movement).
  Toggles SortDirection when clicking the already-sorted column; otherwise sets
  the new SortColumn and resets direction to Ascending.  Then runs SortTree.
  FSorting prevents re-entry from the programmatic SortColumn/SortDirection setters. }
procedure TTyTreeView._HandleHeaderClick(ColIndex: Integer);
var
  col: TTyTreeColumn;
begin
  if FHeader = nil then Exit;
  if (ColIndex < 0) or (ColIndex >= FHeader.Columns.Count) then Exit;

  col := FHeader.Columns.Items[ColIndex] as TTyTreeColumn;

  { Guard: column must allow click and header must have auto-sort on }
  if not (coAllowClick in col.Options) then Exit;
  if not (hoHeaderClickAutoSort in FHeader.Options) then Exit;

  { Update SortColumn / SortDirection (suppress HeaderChanged reentrancy) }
  FSorting := True;
  try
    if FHeader.SortColumn = ColIndex then
    begin
      { Same column — toggle direction }
      if FHeader.SortDirection = sdAscending then
        FHeader.SortDirection := sdDescending
      else
        FHeader.SortDirection := sdAscending;
    end
    else
    begin
      { New column — set it, reset to ascending }
      FHeader.SortColumn    := ColIndex;
      FHeader.SortDirection := sdAscending;
    end;
  finally
    FSorting := False;
  end;

  { Run the sort }
  SortTree(FHeader.SortColumn, FHeader.SortDirection);

  { Fire the event }
  if Assigned(FOnHeaderClick) then
    FOnHeaderClick(Self, ColIndex);

  Invalidate;
end;

{ ── E2 ── SortTree (recursive, lazy-aware) ───────────────────────────────── }

{ SortTreeNode: recursive helper for SortTree.
  Sorts Node's children, then descends into initialized+expanded children.
  Collapsed subtrees are skipped (lazy: they will sort when expanded). }
procedure SortTreeNode(Tree: TTyTreeView; Node: PTyTreeNode;
  Column: Integer; ADirection: TTySortDirection);
var
  child: PTyTreeNode;
begin
  if Node = nil then Exit;
  { Sort this level — DoInit=True so each level materialises + InitNodes its
    children BEFORE comparing (deeper expanded levels have lazy, possibly
    uninitialised children; comparing them zero-filled gives wrong order). }
  Tree.Sort(Node, Column, ADirection, True);
  { Recurse into initialized+expanded children (skip collapsed) }
  child := Node^.FirstChild;
  while child <> nil do
  begin
    if (nsInitialized in child^.States) and (nsExpanded in child^.States) then
      SortTreeNode(Tree, child, Column, ADirection);
    child := child^.NextSibling;
  end;
end;

{ SortTree: sort the whole (initialized+expanded) tree, rebuild the position
  cache, and request a repaint. }
procedure TTyTreeView.SortTree(Column: Integer; ADirection: TTySortDirection);
begin
  if FSorting then Exit;   { reentrancy guard }
  FSorting := True;
  try
    { SortTreeNode sorts FRoot's children (DoInit=True) and recurses into every
      initialized+expanded subtree, materialising + InitNode-ing each level
      before comparing.  (Sorting the root here, NOT a separate Sort(FRoot) call
      first — that double-sorted the root level.) }
    SortTreeNode(Self, FRoot, Column, ADirection);
    { Record the key so HeaderChanged does NOT re-sort on a width/reorder change. }
    FSortedColumn    := Column;
    FSortedDirection := ADirection;
    { The visible order changed — invalidate the position cache }
    FCacheValid := False;
    FRangeY     := ContentHeight;
    Invalidate;
  finally
    FSorting := False;
  end;
end;

{ ── ③e E2 ── inline cell editing (open / commit / cancel + events) ─────────── }

{ CellTextRect — the device-px rect where the painter draws the CAPTION TEXT of
  Node's cell in Column, given the cell band ACellRect (from GetCellRect, already
  client device-px incl. scroll). This is what the inline editor must sit over —
  the bare cell band is NOT it: in the main column the painter first consumes the
  indent + (optional) checkbox slot + (optional) image slot, then draws text at
  captionX + Scale(2); a non-main column just pads the text in by Scale(4).

  KEEP IN SYNC WITH RenderTo's main-column caption layout (lines ~3286–3411 and
  the 0-column twin ~3540–3660) and GetNodeAtPoint's x-zones (~3824–3895): the
  slot conditions + widths below are byte-identical to those paths —
    indentPx     = Scale((level + Ord(FShowRoot)) * FIndent)
    checkbox slot= Scale(16),  reserved iff toCheckSupport + node CheckType<>ctNone
    image slot   = Scale(FIndent), reserved iff FImages assigned + non-empty
    text pad     = Scale(2) (main column) / Scale(4) (other columns)
  Scale(n) here = MulDiv(n, Font.PixelsPerInch, 96), identical to the painter's
  P.Scale and GetNodeAtPoint, so the glue holds at any DPI. }
function TTyTreeView.CellTextRect(Node: PTyTreeNode; Column: Integer;
  const ACellRect: TRect): TRect;
var
  PPI, effCol, level, indentPx, slots: Integer;
  isMain: Boolean;
begin
  Result := ACellRect;
  PPI := Font.PixelsPerInch;

  { Resolve whether Column is the main (chrome-bearing) column. The 0-column (③a)
    tree's single cell IS the main column; in multi-column mode only the cell
    whose index = MainColumn carries indent + slots (NoColumn → MainColumn). }
  if (FHeader = nil) or (FHeader.Columns.Count = 0) then
    isMain := True
  else
  begin
    effCol := Column;
    if effCol = NoColumn then effCol := FHeader.MainColumn;
    isMain := (effCol = FHeader.MainColumn);
  end;

  if isMain then
  begin
    if Node <> nil then
      level := GetNodeLevel(Node)
    else
      level := 0;
    indentPx := MulDiv((level + Ord(FShowRoot)) * FIndent, PPI, 96);
    slots := indentPx;
    if (toCheckSupport in FOptions) and (Node <> nil) and (Node^.CheckType <> ctNone) then
      Inc(slots, MulDiv(16, PPI, 96));
    if (FImages <> nil) and (FImages.Count > 0) then
      Inc(slots, MulDiv(FIndent, PPI, 96));
    Inc(Result.Left, slots + MulDiv(2, PPI, 96));   { captionX + Scale(2) }
    Dec(Result.Right, MulDiv(2, PPI, 96));           { painter's right pad }
  end
  else
  begin
    Inc(Result.Left, MulDiv(4, PPI, 96));            { colMargin = Scale(4) }
    Dec(Result.Right, MulDiv(4, PPI, 96));
  end;

  if Result.Right < Result.Left then Result.Right := Result.Left;   // never inverted
end;

{ EditorBoundsFromCell — position the overlay editor over the painted caption
  text of Node's cell in Column. Delegates the horizontal extent to CellTextRect
  (indent + checkbox + image slots in the main column, the flat text pad
  elsewhere) so the edit text lands ON the caption, not over the chevron/icon.
  Vertically the editor fills the cell band (CellTextRect leaves top/bottom
  untouched) so it lines up with the row. }
function TTyTreeView.EditorBoundsFromCell(Node: PTyTreeNode; Column: Integer;
  const r: TRect): TRect;
begin
  Result := CellTextRect(Node, Column, r);
end;

{ CurrentCellText — the cell's display text, read via the EXACT painter path
  (OnGetTextWithType for the resolved column / ttNormal, falling back to
  OnGetText) so the editor seeds with what's on screen. NoColumn maps to the
  main column (multi-column); the 0-column path simply falls to OnGetText.
  No side effects (never inits the node). }
function TTyTreeView.CurrentCellText(Node: PTyTreeNode; Column: Integer): string;
var
  effCol: Integer;
begin
  Result := '';
  if (Node = nil) or (Node = FRoot) then Exit;
  effCol := Column;
  if (effCol = NoColumn) and (FHeader <> nil) then
    effCol := FHeader.MainColumn;
  if Assigned(FOnGetTextWithType) then
    FOnGetTextWithType(Self, Node, effCol, ttNormal, Result)
  else if Assigned(FOnGetText) then
    FOnGetText(Self, Node, Result);
end;

{ FinishEdit — tear down the active edit: hide the editor, clear the edit state,
  and invalidate so the row repaints with its real caption. Shared by commit and
  cancel; assumes the caller already fired any event. }
procedure TTyTreeView.FinishEdit;
begin
  FEditor.Visible := False;
  FEditing        := False;
  FEditNode       := nil;
  FEditColumn     := NoColumn;
  FEditOriginalText := '';
  { FIX 2 (adversarial): hiding the editor leaves the tree unfocused, so keyboard
    nav dies after every edit. Return focus to the tree on BOTH commit and cancel
    (FinishEdit is the shared teardown). CanSetFocus (the same guard MouseDown
    uses) no-ops cleanly headless / without a handle, so Options=[] is unaffected. }
  if CanSetFocus then SetFocus;
  Invalidate;
end;

{ RepositionEditor — re-glue the open editor to its cell after a layout/scroll
  change. Called from every layout path (scroll setters, expand/collapse,
  InvalidateTreeLayout, column resize/reorder, node-height, Resize) — the
  `not FEditing` guard makes it a no-op when no edit is active, so Options=[] /
  non-editing trees are byte-identical. FEndingEdit additionally short-circuits a
  reposition reached during a commit/cancel teardown (defensive: FinishEdit only
  calls Invalidate, never a layout setter, so this cannot recurse). When the cell
  scrolled out of view (GetCellRect returns False / empty) we commit + close
  (EndEditNode) — Explorer-style; a still-visible cell just re-bounds. }
procedure TTyTreeView.RepositionEditor;
var
  r, cr: TRect;
begin
  if not FEditing or FEndingEdit then Exit;
  if GetCellRect(FEditNode, FEditColumn, r) and not IsRectEmpty(r) then
  begin
    { FIX 4 (adversarial): GetCellRect returns True for a cell scrolled only
      PARTLY out (top above / bottom below the content area — it refuses only when
      the row is ENTIRELY off-screen), and re-bounding it would overlap the header
      band. Treat a row not FULLY inside the vertical content area as scrolled-out:
      commit + close instead of repositioning. }
    cr := ContentRect;
    if (r.Top < cr.Top) or (r.Bottom > cr.Bottom) then
      EndEditNode
    else
      FEditor.BoundsRect := EditorBoundsFromCell(FEditNode, FEditColumn, r);
  end
  else
    EndEditNode;   // scrolled out of view → commit + close
end;

{ EditorKeyDown — Enter commits, Esc cancels; both consume the key. Attached to
  FEditor.OnKeyDown in the ctor. }
procedure TTyTreeView.EditorKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_RETURN: begin EndEditNode; Key := 0; end;
    VK_ESCAPE: begin CancelEdit;  Key := 0; end;
  end;
end;

{ EditorExit — focus left the editor ⇒ commit (Explorer-style). Guarded against
  re-entry during an in-flight teardown (EndEditNode hides the editor, which can
  itself trigger a focus change → OnExit). Attached to FEditor.OnExit in the ctor. }
procedure TTyTreeView.EditorExit(Sender: TObject);
begin
  { FIX 5 (adversarial): a host form tearing down can drop the editor's focus
    while the tree is being destroyed; don't fire a commit (with its event +
    SetFocus) during destruction. The tree's OWN destructor is already safe via
    FEndingEdit, but a closing parent form is not. }
  if csDestroying in ComponentState then Exit;
  if FEditing and not FEndingEdit then EndEditNode;
end;

{ Start editing Node's cell in Column. Returns False when not allowed: not
  toEditable, OnEditing veto, nil node, already editing that same cell, or the
  cell has no visible rect. On success: seeds FEditor with the cell text,
  positions it over the cell, shows + focuses it, and sets the edit state. }
function TTyTreeView.EditNode(Node: PTyTreeNode; Column: Integer): Boolean;
var
  allowed: Boolean;
  r: TRect;
begin
  Result := False;
  if not (toEditable in FOptions) then Exit;
  if (Node = nil) or (Node = FRoot) then Exit;
  { idempotent-safe: re-open of the cell already being edited is a no-op; a
    re-open of a DIFFERENT cell while editing must COMMIT the in-progress edit
    first (FIX 3 adversarial — otherwise the public EditNode silently overwrites
    the edit state and OnNewText never fires for the old cell). }
  if FEditing then
  begin
    if (Node = FEditNode) and (Column = FEditColumn) then Exit(False);
    EndEditNode;
  end;

  { permit / veto (Allowed defaults True). }
  allowed := True;
  if Assigned(FOnEditing) then FOnEditing(Self, Node, Column, allowed);
  if not allowed then Exit;

  { device-px cell rect (incl. scroll). Empty / off-view ⇒ refuse. }
  if not GetCellRect(Node, Column, r) then Exit;
  if IsRectEmpty(r) then Exit;

  { ③e E5: theme the overlay with the tree's controller. ActiveController does
    NOT walk Parent (it is FController-or-TyDefaultController), so a child does
    not inherit the tree's per-instance controller implicitly — assign it here
    (mirrors how the scrollbars get Self.Controller in UpdateScrollbars) so the
    editor resolves the SAME theme as the tree, every time an edit opens.
    DEFERRED N1: the overlay is themed as a TyEdit (font/colors come from the
    TyEdit token, NOT TyTreeNode) — a known deviation if a theme gives the two
    different fonts. DEFERRED N2: a Controller change WHILE an edit is open is not
    propagated to the live overlay until the NEXT EditNode (it is re-assigned only
    here, at open time). }
  FEditor.Controller := Controller;

  FEditOriginalText  := CurrentCellText(Node, Column);
  FEditor.Text       := FEditOriginalText;
  FEditor.BoundsRect := EditorBoundsFromCell(Node, Column, r);
  FEditor.Visible    := True;
  FEditNode          := Node;
  FEditColumn        := Column;
  FEditing           := True;

  { Focus + select-all need a window handle; headless tests never allocate one.
    Guard so they no-op cleanly off-screen (mirrors ③b's MouseCapture lesson). }
  if FEditor.HandleAllocated then
  begin
    if FEditor.CanFocus then FEditor.SetFocus;
    FEditor.SelectAll;
  end;

  Result := True;
end;

{ Commit the active edit: fire OnNewText iff the text changed, then tear down.
  FEndingEdit guards re-entry (a focus-loss commit can fire mid-teardown). }
procedure TTyTreeView.EndEditNode;
begin
  if FEndingEdit then Exit;
  if not FEditing then Exit;
  FEndingEdit := True;
  try
    if (FEditor.Text <> FEditOriginalText) and Assigned(FOnNewText) then
      FOnNewText(Self, FEditNode, FEditColumn, FEditor.Text);
    FinishEdit;
  finally
    FEndingEdit := False;
  end;
end;

{ Discard the active edit: fire OnEditCancelled, then tear down (no commit). }
procedure TTyTreeView.CancelEdit;
begin
  if FEndingEdit then Exit;
  if not FEditing then Exit;
  FEndingEdit := True;
  try
    if Assigned(FOnEditCancelled) then
      FOnEditCancelled(Self, FEditNode, FEditColumn);
    FinishEdit;
  finally
    FEndingEdit := False;
  end;
end;

initialization
  RegisterClass(TTyTreeView);

end.
