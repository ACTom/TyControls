unit tyControls.TreeView;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, Controls, Graphics, LCLType, ImgList,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.ScrollBar;

type
  { C4: hit-test result — which part of a node row the mouse landed in }
  TTyTreeHitPart = (hpNowhere, hpButton, hpImage, hpLabel, hpIndent);

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
    // user data blob (NodeDataSize bytes) follows at offset TreeNodeSize
  end;

  TTyTreeView = class;

  TTyTreeNodeEvent    = procedure(Sender: TTyTreeView; Node: PTyTreeNode) of object;
  TTyTreeChangingEvent = procedure(Sender: TTyTreeView; Node: PTyTreeNode; var Allowed: Boolean) of object;
  TTyTreeInitNodeEvent     = procedure(Sender: TTyTreeView; ParentNode, Node: PTyTreeNode; var InitStates: TTyNodeInitStates) of object;
  TTyTreeInitChildrenEvent = procedure(Sender: TTyTreeView; Node: PTyTreeNode; var ChildCount: Cardinal) of object;
  TTyTreeGetTextEvent  = procedure(Sender: TTyTreeView; Node: PTyTreeNode; var Text: string) of object;

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
    { C3: paint-related fields }
    FHotNode:              PTyTreeNode;   // node under cursor (HotTrack); nil = none
    FOnGetText:            TTyTreeGetTextEvent;
    FOnGetImageIndex:      TTyTreeGetImageIndexEvent;
    FOnGetTextWithType:    TTyTreeGetTextWithTypeEvent;
    FOnPaintText:          TTyTreePaintTextEvent;
    { C4: interaction events }
    FOnNodeClick:          TTyTreeNodeEvent;
    FOnNodeDblClick:       TTyTreeNodeEvent;
    { C4: DblClick tracking — remember which node the MouseDown landed on }
    FLastMouseNode:        PTyTreeNode;
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
    FRangeX:    Integer;        // max content width; set by paint pass (C3); 0 for now
    FSyncingScroll: Boolean;    // reentrancy guard (mirrors ListBox pattern)
    procedure VScrollChange(Sender: TObject);
    procedure HScrollChange(Sender: TObject);
    procedure UpdateScrollBars;
    procedure SetIndent(AValue: Integer);
    procedure SetImages(AValue: TImageList);
    procedure SetShowButtons(AValue: Boolean);
    procedure SetShowTreeLines(AValue: Boolean);
    procedure SetShowRoot(AValue: Boolean);
    procedure SetToggleOnDblClick(AValue: Boolean);
    procedure SetHotTrack(AValue: Boolean);
    { C1: selection internals }
    procedure ClearSelectedNode;
    function  GetSelected(Node: PTyTreeNode): Boolean;
    procedure SetSelected(Node: PTyTreeNode; AValue: Boolean);
    function  GetFocusedNode: PTyTreeNode;
    procedure SetFocusedNode(AValue: PTyTreeNode);
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
    { A5 helpers }
    function  ComputeExpandedSubtreeHeight(Node: PTyTreeNode): Integer;
    function  GetExpanded(Node: PTyTreeNode): Boolean;
    procedure SetExpanded(Node: PTyTreeNode; AValue: Boolean);
  protected
    function GetStyleTypeKey: string; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure Paint; override;
    function  DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
                MousePos: TPoint): Boolean; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DblClick; override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
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
    { C1: selection + focus }
    procedure ClearSelection;
    procedure FullExpand(Node: PTyTreeNode = nil);
    procedure FullCollapse(Node: PTyTreeNode = nil);
    procedure ScrollIntoView(Node: PTyTreeNode);
    property Expanded[Node: PTyTreeNode]: Boolean read GetExpanded write SetExpanded;
    property Selected[Node: PTyTreeNode]: Boolean read GetSelected write SetSelected;
    property FocusedNode: PTyTreeNode read GetFocusedNode write SetFocusedNode;
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
    { C3: paint }
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    { B3: read-only; how many nodes were visited in the last GetNodeAt walk (for perf tests) }
    property LastGetNodeAtVisits: Integer read FLastGetNodeAtVisits;
    { C4: hit-testing }
    function GetNodeAtPoint(X, Y: Integer; out APart: TTyTreeHitPart): PTyTreeNode;
  published
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
    property OnNodeClick:     TTyTreeNodeEvent         read FOnNodeClick     write FOnNodeClick;
    property OnNodeDblClick:  TTyTreeNodeEvent         read FOnNodeDblClick  write FOnNodeDblClick;
    { C3: paint events }
    property OnGetText:       TTyTreeGetTextEvent           read FOnGetText           write FOnGetText;
    property OnGetImageIndex: TTyTreeGetImageIndexEvent     read FOnGetImageIndex     write FOnGetImageIndex;
    property OnPaintText:     TTyTreePaintTextEvent         read FOnPaintText         write FOnPaintText;
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
    ClearSelectedNode;
    Include(Node^.States, nsSelected);
    FSelectedNode := Node;
  end
  else
  begin
    // Deselecting: changed only if this node was the selected one.
    if not (nsSelected in Node^.States) then Exit;
    didChange := True;
    Exclude(Node^.States, nsSelected);
    if FSelectedNode = Node then FSelectedNode := nil;
  end;

  if didChange and Assigned(FOnChange) then
    FOnChange(Self, Node);
  Invalidate;
end;

{ ClearSelection: public — deselects the current node, fires OnChange. }
procedure TTyTreeView.ClearSelection;
var
  prev: PTyTreeNode;
begin
  if FSelectedNode = nil then Exit;
  prev := FSelectedNode;
  Exclude(prev^.States, nsSelected);
  FSelectedNode := nil;
  if Assigned(FOnChange) then FOnChange(Self, prev);
  Invalidate;
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

  Clamp rules (FOffsetY ≤ 0):
    • If node is above the current viewport: FOffsetY := -nodeTop (scroll up).
    • If node is below: FOffsetY := -(nodeTop + NodeHeight - ClientHeight) (scroll down).
    • FOffsetY is clamped to [-(FRangeY - ClientHeight), 0].
      When ClientHeight ≥ FRangeY the clamp collapses to 0 (no scroll needed). }
procedure TTyTreeView.ScrollIntoView(Node: PTyTreeNode);
var
  n:       PTyTreeNode;
  accTop:  Integer;
  viewTop: Integer;      // viewport top in absolute coords = -FOffsetY
  viewBot: Integer;      // viewport bottom in absolute coords
  nodeTop: Integer;
  minOff:  Integer;
begin
  if (Node = nil) or (Node = FRoot) then Exit;

  // Compute the node's absolute top via a visible-order walk.
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

  viewTop := -FOffsetY;
  viewBot := viewTop + ClientHeight;

  if nodeTop < viewTop then
  begin
    // Node is above the viewport — scroll up so node is at the top.
    FOffsetY := -nodeTop;
  end
  else if nodeTop + Integer(Node^.NodeHeight) > viewBot then
  begin
    // Node is below the viewport — scroll down so the bottom of the node is at the bottom.
    FOffsetY := -(nodeTop + Integer(Node^.NodeHeight) - ClientHeight);
  end
  else
    Exit;   // already in view — nothing to do

  // Clamp FOffsetY to [-(FRangeY - ClientHeight), 0]
  minOff := ClientHeight - FRangeY;
  if minOff > 0 then minOff := 0;   // when content shorter than viewport: no negative offset needed
  if FOffsetY < minOff then FOffsetY := minOff;
  if FOffsetY > 0 then FOffsetY := 0;

  UpdateScrollBars;   // sync the scrollbar thumb to the new offset
  Invalidate;
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
    (FRangeX is 0 until the paint pass (C3) sets it; so the bar stays hidden
    in C2.  The plumbing is wired so C3 can just set FRangeX and it will work.)

  FOffsetY is clamped to [-(ContentHeight - viewportH), 0] each call. }
procedure TTyTreeView.UpdateScrollBars;
var
  SBThick, viewW, viewH, contH: Integer;
  wantVScroll, wantHScroll: Boolean;
begin
  SBThick := MulDiv(TyScrollbarSize, Font.PixelsPerInch, 96);

  { Compute viewport dimensions.  Use Height/Width (same as ListBox) so the
    calculation is reliable even without a window handle (headless tests). }
  viewH := Height;
  viewW := Width;
  contH := ContentHeight;

  { Decide which bars are needed.  The presence of a vertical bar steals width
    from the horizontal viewport (and vice-versa), so we must account for that.
    For simplicity we use the same two-pass logic as Memo / ListBox:
      1. Check vertical ignoring the horizontal bar's height.
      2. Adjust viewH for the horizontal bar when it turns out to be visible,
         then re-evaluate whether we still need the vertical bar.
    In ③a the horizontal bar is always hidden (FRangeX = 0), so the second
    pass is a no-op; the pattern is here for C3 to activate. }
  wantVScroll := contH > viewH;
  if wantVScroll then viewW := viewW - SBThick;
  wantHScroll := FRangeX > viewW;
  if wantHScroll then viewH := viewH - SBThick;
  if (not wantVScroll) and (contH > viewH) then
  begin
    wantVScroll := True;
    viewW := Width - SBThick;
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

  step := 3 * FDefaultNodeHeight;
  if WheelDelta > 0 then Delta :=  step   // scroll up
  else                    Delta := -step;  // scroll down

  FOffsetY := FOffsetY + Delta;
  UpdateScrollBars;   // clamps FOffsetY and syncs thumb
  Invalidate;
  Result := True;
end;

{ Resize — recalculate scrollbar visibility/geometry on layout change. }
procedure TTyTreeView.Resize;
begin
  inherited Resize;
  UpdateScrollBars;
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
  UpdateScrollBars;
  Invalidate;
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
  dh, dc: Integer;
begin
  if (Node = nil) or (Node = FRoot) then Exit;

  // Null out selection/focus if this node (or an ancestor) is being deleted
  if FFocusedNode = Node then FFocusedNode := nil;
  if FSelectedNode = Node then
  begin
    Exclude(Node^.States, nsSelected);
    FSelectedNode := nil;
  end;

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

  FreeNodeMem(Node);
  InvalidateTreeLayout;
end;

procedure TTyTreeView.Clear;
begin
  while FRoot^.FirstChild <> nil do DeleteNode(FRoot^.FirstChild);
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

procedure TTyTreeView.InitNode(Node: PTyTreeNode);
var
  initStates: TTyNodeInitStates;
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
begin
  UpdateScrollBars;   // keep scrollbar range current (cheap; no-op when clean)

  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;

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

    { ── Empty tree ───────────────────────────────────────────────────────── }
    if FRoot^.FirstChild = nil then
    begin
      if FEmptyListMessage <> '' then
      begin
        NodeStyle := ActiveController.Model.ResolveStyle('TyTreeNode', '', []);
        P.DrawText(CR, FEmptyListMessage, S.FontName, ResolveFontSize(S), S.FontWeight,
          NodeStyle.TextColor, taCenter, tlCenter, True);
      end;
      P.EndPaint;
      Exit;
    end;

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

    { ── First on-screen node ─────────────────────────────────────────────── }
    firstNodeY := -FOffsetY;
    if firstNodeY < 0 then firstNodeY := 0;
    node := GetNodeAt(firstNodeY, firstTop);
    if node = nil then
    begin
      P.Bitmap.ClipRect := savedClip;
      P.EndPaint;
      Exit;
    end;
    { The first row may be partially scrolled above the viewport.
      rowTop = device-Y where the first row's TOP pixel should be drawn. }
    rowTop := CR.Top - (firstNodeY - firstTop);

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

      { ── Image ────────────────────────────────────────────────────────── }
      captionX := contentLeft + indentPx;
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
        if (imgIdx >= 0) and (imgIdx < FImages.Count) then
        begin
          { Draw images directly to the underlying Canvas.  The BGRA bitmap and
            the ACanvas share the same device context, so this is safe as long as
            we blit into the device-space rect (offset by ARect.Left/Top). }
          FImages.Draw(ACanvas,
            ARect.Left + captionX,
            ARect.Top  + rowTop + (rowH - FImages.Height) div 2,
            imgIdx);
        end;
        Inc(captionX, imgSlotW);
      end;

      { ── Caption ─────────────────────────────────────────────────────── }
      txt := '';
      if Assigned(FOnGetText) then
        FOnGetText(Self, node, txt);

      textRect := Rect(captionX + P.Scale(2), rowTop, CR.Right, rowTop + rowH);
      if (textRect.Left < textRect.Right) and (txt <> '') then
        P.DrawText(textRect, txt,
          NodeStyle.FontName, ResolveFontSize(NodeStyle), NodeStyle.FontWeight,
          NodeStyle.TextColor, taLeftJustify, tlCenter, True);

      if Assigned(FOnPaintText) then
        FOnPaintText(Self, ACanvas, node, -1, ttNormal);

      { ── FRangeX accumulation ─────────────────────────────────────────── }
      { Pure content WIDTH for this row — independent of CR.Left and FOffsetX so
        the H-scroll range never drifts with the scroll position.  Equals the
        rendered layout: indent + (image slot if used) + gap + text + tail. }
      if txt <> '' then
      begin
        measW := indentPx + usedImgSlotW + P.Scale(2) +
          P.MeasureText(txt, NodeStyle.FontName, ResolveFontSize(NodeStyle),
                        NodeStyle.FontWeight).cx + P.Scale(4);
        if measW > rangeXNew then
          rangeXNew := measW;
      end;

      node   := GetNextVisibleNoInit(node);
      Inc(rowTop, rowH);
    end;

    P.Bitmap.ClipRect := savedClip;
    P.EndPaint;
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

{ GetNodeAtPoint
  Convert client (X, Y) to the absolute content coordinate space, find the
  node under the cursor via GetNodeAt, then classify which column slot was hit.

  X-accumulation mirrors RenderTo EXACTLY (same scale, same formula):
    CR      = ContentRect (padding-inset + scrollbar-shrunk)
    indentPx = Scale((level + Ord(FShowRoot)) * FIndent)
    btnSlotW = Scale(FIndent)   — one Indent-wide slot before indentPx
    imgSlotW = Scale(FIndent)   — one Indent-wide slot after indentPx

  The absolute content X/Y:
    absY = (Y - CR.Top) + (-FOffsetY)
    absX = (X - CR.Left) + (-FOffsetX)  }
function TTyTreeView.GetNodeAtPoint(X, Y: Integer; out APart: TTyTreeHitPart): PTyTreeNode;
var
  PPI: Integer;
  CR: TRect;
  absY, absX: Integer;
  nodeTop: Integer;
  node: PTyTreeNode;
  level, indentPx, btnSlotW, imgSlotW: Integer;
  captionX: Integer;
begin
  Result   := nil;
  APart    := hpNowhere;

  PPI := Font.PixelsPerInch;
  CR  := ContentRect;

  { Convert to content-space coordinates }
  absY := (Y - CR.Top)  + (-FOffsetY);
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
      [0 .. indentPx - btnSlotW)   = hpIndent (the left-padding area)
      [indentPx - btnSlotW .. indentPx) = hpButton slot (only when nsHasChildren)
      [indentPx .. indentPx + imgSlotW) = hpImage (only when FImages assigned)
      [indentPx or beyond caption)       = hpLabel                            }

  if absX < 0 then
  begin
    APart := hpIndent;
    Result := node;
    Exit;
  end;

  if absX < indentPx - btnSlotW then
  begin
    APart  := hpIndent;
    Result := node;
    Exit;
  end;

  if (absX < indentPx) then
  begin
    { In the button slot — classify as hpButton only if the node has children
      AND buttons are shown.  Otherwise treat as hpIndent. }
    if FShowButtons and (nsHasChildren in node^.States) then
      APart := hpButton
    else
      APart := hpIndent;
    Result := node;
    Exit;
  end;

  { Past the indent zone }
  captionX := indentPx;
  if (FImages <> nil) and (FImages.Count > 0) then
  begin
    if absX < captionX + imgSlotW then
    begin
      APart  := hpImage;
      Result := node;
      Exit;
    end;
    Inc(captionX, imgSlotW);
  end;

  { Everything to the right of the image slot is the label area }
  APart  := hpLabel;
  Result := node;
end;

procedure TTyTreeView.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  part: TTyTreeHitPart;
  node: PTyTreeNode;
begin
  inherited MouseDown(Button, Shift, X, Y);

  if not Enabled then Exit;

  { Request keyboard focus so arrow-key navigation works after click }
  if CanSetFocus then SetFocus;

  node := GetNodeAtPoint(X, Y, part);
  FLastMouseNode := node;

  if Button = mbLeft then
  begin
    if node = nil then Exit;

    if part = hpButton then
    begin
      { Click on the expand/collapse button — toggle, do NOT change selection }
      Expanded[node] := not Expanded[node];
    end
    else
    begin
      { Click on any other part (label, image, indent) — focus the node }
      FocusedNode := node;
      if Assigned(FOnNodeClick) then FOnNodeClick(Self, node);
    end;
  end
  else if Button = mbRight then
  begin
    { Right-click: select the node if not already selected }
    if (node <> nil) and not (nsSelected in node^.States) then
      FocusedNode := node;
  end;
end;

procedure TTyTreeView.DblClick;
var
  node: PTyTreeNode;
begin
  inherited DblClick;
  { FLastMouseNode was set by the preceding MouseDown; use it here so we don't
    need to re-probe the mouse position (which may have drifted). }
  node := FLastMouseNode;
  if node = nil then Exit;

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
begin
  inherited MouseMove(Shift, X, Y);

  if not FHotTrack then Exit;

  node := GetNodeAtPoint(X, Y, part);
  if node <> FHotNode then
  begin
    FHotNode := node;
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
begin
  inherited KeyDown(Key, Shift);

  cur := FFocusedNode;

  case Key of

    VK_DOWN:
    begin
      if cur = nil then
        nxt := GetFirstVisibleNoInit
      else
        nxt := GetNextVisibleNoInit(cur);
      if nxt <> nil then
      begin
        FocusedNode := nxt;
        ScrollIntoView(nxt);
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
          FocusedNode := nxt;
          ScrollIntoView(nxt);
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
        FocusedNode := nxt;
        ScrollIntoView(nxt);
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
        FocusedNode := nxt;
        ScrollIntoView(nxt);
      end;
      Key := 0;
    end;

    VK_PRIOR:  { Page Up }
    begin
      if cur <> nil then
      begin
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

  end;
end;

end.

initialization
  RegisterClass(TTyTreeView);
