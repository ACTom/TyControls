unit tyControls.TreeView;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, Controls, Graphics, LCLType, LCLIntf, LazUTF8, ImgList,
  { StdCtrls: TScrollStyle, so ScrollBars means the same thing here as on TTyMemo and
    on LCL's own TCustomTreeView. ComCtrls: THitTests/THitTest — GetHitTestInfoAt has
    to return LCL's OWN set type or ported `htOnButton in Tree.GetHitTestInfoAt(X,Y)`
    still will not compile, which is the whole point of having the method. }
  StdCtrls, ComCtrls,
  BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller, tyControls.ScrollBar,
  tyControls.Columns, tyControls.Edit;

type
  { C4: hit-test result — which part of a node row the mouse landed in }
  TTyTreeHitPart = (hpNowhere, hpButton, hpImage, hpLabel, hpIndent,
                    hpHeaderSection, hpHeaderDivider,
                    hpCheckBox);   { B3: the checkbox slot in the main column }

  { Where one node's chrome slots and caption sit INSIDE one cell. Device px,
    all absolute (already offset by the cell left the caller passed in).

    A main-column cell lays out in READING order:
        [ ...indent... ][ button ][ checkbox? ][ image? ][ caption ]
                        ^ButtonSlotX          ^ImageX    ^CaptionX
                                  ^CheckX
    where the button slot is the Indent-wide strip ENDING at IndentPx (it sits
    inside the indent, not after it), and the optional slots are present only when
    CheckW / ImageW are non-zero. A non-main cell has no chrome: the caption spans
    the cell and TextPad is the only inset.

    The caption's x used to be re-accumulated by four separate `Inc(captionX, ..)`
    runs -- two paints, the hit test and CellTextRect -- under a comment asking a
    human to keep them in step. This record is what they now all read.

    MIRRORING, and what the four *X fields mean when it happens.

    They stay PHYSICAL LEFT EDGES. Right-to-left, the picture above is reflected inside
    the cell, so the indent is against the cell's RIGHT edge and the caption against its
    left -- but ButtonSlotX is still the smaller x of the button slot, CheckX still the
    smaller x of the check slot, and so on. That is a decision, and the reason for it is
    the consumers: five of the six turn a slot into a rectangle as [X, X+W), an expression
    that is correct in BOTH directions only while X is the physical left. Renaming these
    to "leading edge" would silently invert all five and force each one to re-derive
    `X - W` under mirroring -- five new x computations in a control family whose entire
    recent history is the removal of duplicated x computations.

    The one consumer that reads an ORDER rather than a rectangle is the hit-test ladder in
    GetNodeAtPoint, and one direction bit serves it exactly. Hence RightToLeft below.

    CaptionRight exists for the same reason the four keep their meaning: the caption is a
    REMAINDER, not a fixed-width slot, so it is the one piece that needs both of its edges
    named. Left-to-right it is the cell's right edge and nothing has changed; mirrored it
    is where the icon slot begins. A consumer that kept using the cell's own right edge
    would draw the caption straight through the chrome. }
  TTyTreeCaptionSlots = record
    IndentPx:    Integer;   { Scale((level + Ord(ShowRoot)) * Indent) }
    ButtonSlotX: Integer;   { LEFT of the expander slot, in either direction }
    ButtonSlotW: Integer;   { Scale(Indent) }
    CheckX:      Integer;   { LEFT of the checkbox slot; valid iff CheckW > 0 }
    CheckW:      Integer;   { Scale(16), or 0 when this node shows no checkbox }
    ImageX:      Integer;   { LEFT of the image slot; valid iff ImageW > 0 }
    ImageW:      Integer;   { Scale(Indent), or 0 when no image list is assigned }
    CaptionX:    Integer;   { LEFT of the caption region, BEFORE TextPad }
    CaptionRight:Integer;   { RIGHT of the caption region, before the same pad }
    TextPad:     Integer;   { Scale(2) in the main column, Scale(4) elsewhere }
    RightToLeft: Boolean;   { the direction the walk ran in; read by the hit-test ladder }
  end;

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
    == ③d. Appended last so the existing ordinals are undisturbed.
    ③f F2: toNodeDrag opts a tree into intra-tree node drag-drop (drag a node to
    reorder among siblings / reparent), via the MoveNode engine + a thin mouse
    state machine. Default off ⇒ no drag, == ③e. Appended last (ordinals stable). }
  TTyTreeOption = (toMultiSelect, toCheckSupport, toFullRowSelect,
                   toAutoTristateTracking, toVariableNodeHeight,
                   toIncrementalSearch, toOwnerDraw, toEditable, toNodeDrag);
  TTyTreeOptions = set of TTyTreeOption;

  { ③f F1: drop position relative to a target node, for the intra-tree node
    drag-drop move engine. dmNone = no valid drop (empty area / vetoed);
    dmAbove/dmBelow = reorder as ATarget's preceding/following sibling;
    dmOn = reparent as ATarget's last child. }
  TTyTreeDropMode = (dmNone, dmAbove, dmOn, dmBelow);

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

  { ③f F2: intra-tree drag events.
    OnNodeDragOver — per-target/-mode veto fired while dragging. Allowed enters as
                 CanMoveNode(Src, Target, Mode); the handler may only FURTHER
                 restrict (setting Allowed:=True on an invalid move is still
                 blocked by MoveNode's own guard — CanMoveNode is the hard gate).
    OnNodeMoved reuses TTyTreeNodeEvent (Sender; Node) — fired after a successful
                drop (Node.Parent is the new parent; Index re-stamped).

    BREAKING (parity): this event used to be published as `OnDragOver`, which is the
    name TControl already uses for the LCL drag-and-drop hook that the base class
    publishes (tyControls.Base.pas:299). One control shadowing that name with an
    unrelated signature meant the tree was the ONE TTy control that could not be
    wired as an LCL drop target — assigning a TDragOverEvent there was a type error.
    Migration: rename the handler assignment to OnNodeDragOver; `OnDragOver` is back
    to being LCL's. }
  TTyTreeDragOverEvent = procedure(Sender: TTyTreeView; Src, Target: PTyTreeNode;
    Mode: TTyTreeDropMode; var Allowed: Boolean) of object;

  { LCL parity: one end-of-edit notification, fired exactly once per editing session
    whether the edit committed or was abandoned (comctrls.pp:2935 TTVEditingEndEvent).
    OnNewText/OnEditCancelled remain the two half-events; "the editor closed, re-enable
    my buttons" is this one. }
  TTyTreeEditingEndEvent = procedure(Sender: TTyTreeView; Node: PTyTreeNode;
    Column: Integer; Cancel: Boolean) of object;

  { LCL parity: the plain-function compare CustomSort takes (comctrls.pp:2965
    TTreeNodeCompare). A function, not a method pointer — that is the whole point of
    the LCL member: a one-off sort order should not need an object to hang on. }
  TTyTreeNodeCompare = function(Node1, Node2: PTyTreeNode): Integer;

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

{ ==========================================================================
  条目模型(TTyTreeNodes / TTyTreeNodeItem)—— 为什么它存在,以及它凭什么
  不动虚拟内核

  本控件是**虚拟树**:节点是定长记录,标题由 OnGetText 现算,百万节点是它的
  卖点。LCL 的 TTreeView 恰好相反:Items 是一棵 TTreeNode 对象树,每个节点自己
  拿着 Text,能进 .lfm,设计器里有节点编辑器。两者看上去互斥 —— 但**本库一个
  文件之外已经把这道题做完了**:TTyListView 同时有 TTyListItems 集合和
  OwnerData 虚拟模式,靠一个显式开关选路,并且"只有一处 if OwnerData"
  (见 tyControls.ListView.pas §"The single data intake")。

  这里照抄那条约定,只改一处:模式不是布尔开关,而是 **Items 空不空**。
  原因是默认值:TTyListView 的默认是集合模式,所以 OwnerData 默认 False 读得通;
  本控件的默认从第一天起就是虚拟模式,一个同名的 OwnerData 就得默认 True ——
  隔壁同名同义的属性一个默认 False 一个默认 True,比没有开关更坏。
  而"Items 非空"不是对旧行为的推断:**空 Items 是今天所有代码的状态**,
  非空 Items 是一个以前根本不可能出现的新状态,所以虚拟路径逐字节不变。

  两个来源同时出现怎么办 —— 这是本轮一直在清理的那类缺陷,所以**报错,不择一**:
  Items 非空的同时再挂 OnGetText / OnGetTextWithType,或者反过来,抛
  ETyTreeItemMode 并在消息里同时点名两边。静默偏向任何一边都会变成
  "设计器里填的节点在运行时不见了"或者"我的 OnGetText 不触发了"这种
  查半天的 bug。流式化期间(csLoading)冲突只记账,到 Loaded 再抛,
  否则 .lfm 里属性顺序会决定报不报错。

  形状:**扁平集合 + Level 缩进**,不是对象树。三个理由 ——
  ① TCollection 的流式化与 OI 集合编辑器都是现成的,.lfm 里是**可读可 diff 的
     文本块**,比 LCL 那个 Items.Data 十六进制 blob 好;
  ② 集合顺序天然就是**前序**,于是 Items[i] 与 LCL 的绝对下标语义逐个对上;
  ③ 父子关系由 Level 推出,AddChild 只是"插在父子树末尾、Level+1"。

  代价(诚实记账):条目模式下节点数据块的头 4 字节被控件征用为条目下标,
  所以 NodeDataSize 与 Items 也互斥(同样报错)。虚拟模式下这 4 字节不存在,
  分配步长与从前完全一样。
  ========================================================================== }

  ETyTreeItemMode = class(Exception);

  TTyTreeNodes = class;

  { 一个条目 = 一个节点。published 的部分进 .lfm 与对象查看器;
    Data 是 app 的负载(不流式化),Node 是物化之后的记录指针。 }
  TTyTreeNodeItem = class(TCollectionItem)
  private
    FText:          TCaption;
    FLevel:         Integer;
    FImageIndex:    Integer;
    FSelectedIndex: Integer;
    FExpanded:      Boolean;
    FCheckType:     TTyCheckType;
    FCheckState:    TTyCheckState;
    FData:          Pointer;
    FNode:          PTyTreeNode;
    function  GetTreeNodes: TTyTreeNodes;
    procedure SetText(const AValue: TCaption);
    procedure SetLevel(AValue: Integer);
    procedure SetImageIndex(AValue: Integer);
    procedure SetSelectedIndex(AValue: Integer);
    procedure SetExpanded(AValue: Boolean);
    procedure SetCheckType(AValue: TTyCheckType);
    procedure SetCheckState(AValue: TTyCheckState);
  protected
    function GetDisplayName: string; override;
  public
    constructor Create(ACollection: TCollection); override;
    procedure Assign(ASource: TPersistent); override;
    { 结构导航 —— 全部从扁平序 + Level 推出,LCL 的 TTreeNode 同名成员语义。 }
    function  Parent: TTyTreeNodeItem;
    function  Count: Integer;                              { 直接子条目数 }
    function  Items(AIndex: Integer): TTyTreeNodeItem;     { 第 AIndex 个直接子条目 }
    function  HasChildren: Boolean;
    { 本条目子树(含自身)占的条目个数 —— 插入点计算用。 }
    function  SubTreeCount: Integer;
    property  Data: Pointer read FData write FData;
    { 物化之后对应的记录节点;未物化 / 虚拟模式下为 nil。只读:节点由条目层建。 }
    property  Node: PTyTreeNode read FNode;
    property  TreeNodes: TTyTreeNodes read GetTreeNodes;
  published
    { 节点标题。条目模式下这是标题的**唯一**来源(DoGetText 从这里取)。 }
    property Text:          TCaption      read FText          write SetText;
    { 缩进层级 = 树形。0 是顶层;每一项至多比**前一项**深 1 层(越界会被夹紧),
      于是任何一串 Level 都对应唯一一棵合法的树,.lfm 里手写也不会崩。 }
    property Level:         Integer       read FLevel         write SetLevel default 0;
    property ImageIndex:    Integer       read FImageIndex    write SetImageIndex default -1;
    property SelectedIndex: Integer       read FSelectedIndex write SetSelectedIndex default -1;
    property Expanded:      Boolean       read FExpanded      write SetExpanded default False;
    property CheckType:     TTyCheckType  read FCheckType     write SetCheckType default ctNone;
    property CheckState:    TTyCheckState read FCheckState    write SetCheckState default csUnchecked;
  end;

  { 条目集合。顺序 = 前序遍历序,所以 Count / Item[i] 与 LCL 的
    TTreeNodes.Count / Item[i](绝对下标)是同一个意思。 }
  TTyTreeNodes = class(TCollection)
  private
    FOwner:      TPersistent;
    FStructural: Boolean;   { 本批变更动了树形(增删 / Level),EndUpdate 时要重建 }
    function  GetItem(AIndex: Integer): TTyTreeNodeItem;
    procedure SetItem(AIndex: Integer; AValue: TTyTreeNodeItem);
    function  GetTopLvlCount: Integer;
    function  GetTopLvlItems(AIndex: Integer): TTyTreeNodeItem;
    { 在 AIndex 处插入一个 Level=ALevel 的条目(内部,已算好落点)。 }
    function  InsertAt(AIndex, ALevel: Integer; const S: string): TTyTreeNodeItem;
  protected
    function  GetOwner: TPersistent; override;
    { 变更传给控件的唯一两条路:Notify 记下"这一批动了树形",
      Update 决定整棵重建还是只回写那一个节点。 }
    procedure Notify(Item: TCollectionItem; Action: TCollectionNotification); override;
    procedure Update(Item: TCollectionItem); override;
  public
    constructor Create(AOwner: TPersistent);
    { LCL TTreeNodes 的建节点 API(comctrls.pp)。ASibling / AParent 为 nil = 顶层。 }
    function Add(ASibling: TTyTreeNodeItem; const S: string): TTyTreeNodeItem;
    function AddFirst(ASibling: TTyTreeNodeItem; const S: string): TTyTreeNodeItem;
    function AddChild(AParent: TTyTreeNodeItem; const S: string): TTyTreeNodeItem;
    function AddChildFirst(AParent: TTyTreeNodeItem; const S: string): TTyTreeNodeItem;
    function Insert(ASibling: TTyTreeNodeItem; const S: string): TTyTreeNodeItem;
    { 删除一个条目**连同它的整棵子树** —— 光 Delete(i) 会把子条目留成孤儿
      (它们的 Level 突然比前一项深 2 层),所以删子树必须是一个动作。 }
    procedure DeleteItem(AItem: TTyTreeNodeItem);
    function  GetFirstNode: TTyTreeNodeItem;
    property Items[AIndex: Integer]: TTyTreeNodeItem read GetItem write SetItem; default;
    property TopLvlCount: Integer read GetTopLvlCount;
    property TopLvlItems[AIndex: Integer]: TTyTreeNodeItem read GetTopLvlItems;
  end;

  TTyTreeView = class(TTyCustomControl)
  private
    FRoot: PTyTreeNode;
    FNodeDataSize: Integer;     // -1 until set
    FNodeAllocSize: Integer;    // TreeNodeSize + Max(0, FNodeDataSize)
    { 条目模型(见单元中部 §条目模型)。FItemMode 只由 RebuildFromItems 改;
      FRebuildingItems 是物化期间给虚拟 API 开的唯一后门;FPendingConflict 存
      csLoading 期间发现、要留到 Loaded 才抛的冲突消息。 }
    FItems:            TTyTreeNodes;
    FItemMode:         Boolean;
    FRebuildingItems:  Boolean;
    FPendingConflict:  string;
    FDefaultNodeHeight: Integer;         { classic fallback (18); the density value comes
                                           from GetDefaultNodeHeight unless explicitly pinned }
    FDefaultNodeHeightExplicit: Boolean; { True once a host/.lfm sets DefaultNodeHeight; False =
                                           follow the theme's --item-height token (18 classic / 38 modern) }
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
    FOnEditingEnd:         TTyTreeEditingEndEvent;
    { LCL parity: the vetoable half of the selection change (comctrls.pp:3669). Every
      other selection notification we had -- OnChange, OnFocusChanged,
      OnSelectionChanged -- fires after the move, so "you have unsaved edits, stay on
      this node" was not expressible even though the veto shape already existed here
      for expand/collapse and check. }
    FOnChanging:           TTyTreeChangingEvent;
    { SetFocusedNode asks OnChanging, then delegates to SetSelected, which would ask
      again for the same gesture. One question per gesture. }
    FSuppressChanging:     Boolean;
    { ③f F2: intra-tree node-drag state machine (gated by toNodeDrag). The drag
      lives entirely on the control (no node-record growth). FDragNode is the
      pressed node (ARMED on MouseDown over a label/image); FDragActive flips True
      once MouseMove passes the Scale(4) manhattan threshold; FDropTarget/FDropMode
      are the tracked drop position (updated each MouseMove while active, consumed
      by MouseUp + the F3 drop-mark). }
    FDragNode:             PTyTreeNode;
    FDragActive:           Boolean;
    FDragStartPos:         TPoint;
    FDropTarget:           PTyTreeNode;
    FDropMode:             TTyTreeDropMode;
    { A15: both the drag feedback (crDrag/crNoDrop) and the column-divider hint
      (crHSplit) borrow Cursor for the duration of a gesture. They used to hand it
      back as crDefault, which quietly destroyed a caller's own Cursor setting --
      set crHandPoint on a tree, hover a divider once, and it is gone for good.
      Remember what was there and restore THAT. }
    FSavedCursor:          TCursor;
    FCursorOverridden:     Boolean;
    FOnDragOver:           TTyTreeDragOverEvent;
    FOnNodeMoved:          TTyTreeNodeEvent;
    { C1: layout / display properties }
    FIndent:            Integer;
    { LCL takes any TCustomImageList here (comctrls.pp:3768). Ours took the narrower
      TImageList, so a TCustomImageList-typed reference -- TLCLGlyphs, or any custom
      descendant that is not a TImageList -- would not assign. }
    FImages:            TCustomImageList;
    FEmptyListMessage:  string;
    FShowButtons:       Boolean;
    FShowTreeLines:     Boolean;
    FShowRoot:          Boolean;
    FToggleOnDblClick:  Boolean;
    FHotTrack:          Boolean;
    { LCL parity block — every one of these exists on TCustomTreeView.
      FScrollBars      comctrls.pp:3777, default ssBoth. Ours always created both bars
                       and decided visibility purely from content extent, so ssNone
                       (a tree inside an outer scroller) was unreachable.
      FAutoExpand      comctrls.pp:3654, default False.
      FRightClickSelect
                       comctrls.pp:3695. NOTE the default: LCL ships False, ours has
                       always moved focus on right-down (see MouseDown) and shipping
                       controls depend on it, so ours defaults True. Set it False for
                       LCL's behaviour.
      FHideSelection   comctrls.pp:3656, default True — dim the selection when the
                       control does not have focus, so two adjacent trees do not both
                       look active.
      FShowSeparators  comctrls.pp:3703, default False — a rule under each top-level row. }
    FScrollBars:        TScrollStyle;
    FAutoExpand:        Boolean;
    FRightClickSelect:  Boolean;
    FHideSelection:     Boolean;
    FShowSeparators:    Boolean;
    { C2: embedded scrollbars + offsets }
    FVScroll:   TTyScrollBar;   // vertical; created in constructor (never nil after Create)
    FHScroll:   TTyScrollBar;   // horizontal; created in constructor (never nil after Create)
    FOffsetY:   Integer;        // ≤ 0; how many pixels the viewport is scrolled down
    FOffsetX:   Integer;        // ≤ 0; how many pixels the viewport is scrolled right
    FRangeX:    Integer;        // max content width; accumulated by paint pass (C3); reset to 0 by InvalidateTreeLayout on every structural change
    FSyncingScroll: Boolean;    // reentrancy guard (mirrors ListBox pattern)
    { B (columns): header sub-object }
    FHeader:    TTyHeader;
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
    FCustomSortProc:   TTyTreeNodeCompare;   { live only for the duration of CustomSort }
    { B1: tree option flags }
    FOptions:          TTyTreeOptions;
    procedure OverrideCursor(AOn: Boolean; AWith: TCursor);

    procedure SetOptions(AValue: TTyTreeOptions);
    { density: stored-sentinel accessors for the default node/row height. Reading
      returns the pinned value when explicit, else the --item-height token. }
    function  GetDefaultNodeHeight: Integer;
    procedure SetDefaultNodeHeight(AValue: Integer);
    { ③d B1: per-node row-height accessors (variable height) }
    function  GetNodeHeight(Node: PTyTreeNode): Integer;
    procedure SetNodeHeight(Node: PTyTreeNode; AValue: Integer);
    { ③d C1: incremental-search internals }

    function  NodeMatchesSearch(Node: PTyTreeNode; const ASearchText: string): Boolean;
    procedure DoIncrementalSearch;                                 // walk visible nodes from focus (wrapping)
    { B1: check property raw accessors }
    function  GetCheckType(Node: PTyTreeNode): TTyCheckType;
    procedure SetCheckType(Node: PTyTreeNode; AValue: TTyCheckType);
    function  GetCheckState(Node: PTyTreeNode): TTyCheckState;
    procedure SetCheckState(Node: PTyTreeNode; AValue: TTyCheckState);
    function  GetChecked(Node: PTyTreeNode): Boolean;
    procedure SetChecked(Node: PTyTreeNode; AValue: Boolean);
    { 方向键的两个动作:向"深"走(展开 / 进第一个子节点)与向"浅"走(收起 / 回父节点)。
      抽成两个方法而不是在 KeyDown 里写两遍 `if RtlLayout`:方向键漏翻是本程序记在案的
      第三号静默故障,而"翻了一个没翻另一个"的树是**收得起、再也打不开**。
      分开之后这种状态在结构上写不出来。 }
    procedure KeyStepIn(Node: PTyTreeNode);
    procedure KeyStepOut(Node: PTyTreeNode);
    { E3: internal — process a header section click (toggle sort direction / set sort column) }
    procedure _HandleHeaderClick(ColIndex: Integer);
    procedure VScrollChange(Sender: TObject);
    procedure HScrollChange(Sender: TObject);
    procedure UpdateScrollBars;
    { B (columns): header/column change handler }
    procedure HeaderChanged(Sender: TObject);
    procedure SetHeader(AValue: TTyHeader);
    procedure SetIndent(AValue: Integer);
    procedure SetImages(AValue: TCustomImageList);
    procedure SetShowButtons(AValue: Boolean);
    procedure SetShowTreeLines(AValue: Boolean);
    procedure SetShowRoot(AValue: Boolean);
    procedure SetToggleOnDblClick(AValue: Boolean);
    procedure SetHotTrack(AValue: Boolean);
    { LCL parity accessors }
    procedure SetScrollBars(AValue: TScrollStyle);
    procedure SetHideSelection(AValue: Boolean);
    procedure SetShowSeparators(AValue: Boolean);
    { LCL names for four switches that only existed as Options set members / under a
      different spelling. Read/write pass-throughs, no second copy of the state. }
    function  GetRowSelect: Boolean;
    procedure SetRowSelect(AValue: Boolean);
    function  GetMultiSelect: Boolean;
    procedure SetMultiSelect(AValue: Boolean);
    function  GetShowLines: Boolean;
    procedure SetShowLines(AValue: Boolean);
    function  GetReadOnly: Boolean;
    procedure SetReadOnly(AValue: Boolean);
    { LCL parity: Selected as THE current node (comctrls.pp:3778). }
    function  GetSelection: PTyTreeNode;
    procedure SetSelection(AValue: PTyTreeNode);
    function  GetSelections(AIndex: Integer): PTyTreeNode;
    { per-node Visible / HasChildren }
    function  GetNodeVisible(Node: PTyTreeNode): Boolean;
    procedure SetNodeVisible(Node: PTyTreeNode; AValue: Boolean);
    function  GetHasChildren(Node: PTyTreeNode): Boolean;
    procedure SetHasChildren(Node: PTyTreeNode; AValue: Boolean);
    { writable scroll position }
    function  GetTopItem: PTyTreeNode;
    procedure SetTopItem(AValue: PTyTreeNode);
    function  GetBottomItem: PTyTreeNode;
    function  GetScrolledTop: Integer;
    procedure SetScrolledTop(AValue: Integer);
    function  GetScrolledLeft: Integer;
    procedure SetScrolledLeft(AValue: Integer);
    { Visible[] bookkeeping: like AdjustTotalHeight but it does NOT touch Node's own
      TotalHeight — hiding a node must not destroy the subtree total we need to add
      back when it is shown again. }
    procedure AdjustAncestorsHeight(Node: PTyTreeNode; Delta: Integer);
    { AlphaSort's / CustomSort's stand-in compare handlers (see AlphaSort). }
    procedure AlphaCompare(Sender: TTyTreeView; Node1, Node2: PTyTreeNode;
      Column: Integer; var CompareResult: Integer);
    procedure CustomSortCompare(Sender: TTyTreeView; Node1, Node2: PTyTreeNode;
      Column: Integer; var CompareResult: Integer);
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
    { --- 条目模型的控件侧(见单元中部 §条目模型)------------------------------ }
    procedure SetItems(AValue: TTyTreeNodes);
    procedure SetOnGetText(AValue: TTyTreeGetTextEvent);
    procedure SetOnGetTextWithType(AValue: TTyTreeGetTextWithTypeEvent);
    { 分配步长的唯一出口:条目模式征用块首 4 字节存条目下标;虚拟模式与从前一样。 }
    procedure UpdateNodeAllocSize;
    { 冲突闸门。ARaise 描述"另一边是谁";csLoading 期间只记账,Loaded 再抛。 }
    procedure ItemModeConflict(const AWhat: string);
    { 虚拟结构 API 的入口守卫(RootNodeCount / SetChildCount / AddChild)。 }
    procedure GuardVirtualStructure(const AWhat: string);
    { Items 变了:结构变更整棵重建,属性变更只回写那一个节点。 }
    procedure ItemsStructureChanged;
    procedure ItemStateChanged(AItem: TTyTreeNodeItem);
    procedure RebuildFromItems;
    procedure ApplyItemToNode(AItem: TTyTreeNodeItem);
    procedure StampItemRef(ANode: PTyTreeNode; AItemIndex: Integer);
    function  GetNodeItem(Node: PTyTreeNode): TTyTreeNodeItem;
    function  GetNodeText(Node: PTyTreeNode): string;
    procedure AdjustTotalCount(Node: PTyTreeNode; Delta: Integer);
    procedure AdjustTotalHeight(Node: PTyTreeNode; Delta: Integer);
    { ③c A1 / ③f F1: re-stamp a parent's child list with consecutive 0-based Index
      values. Shared by DeleteNode (sibling renumber after a removal) and MoveNode. }
    procedure ReindexSiblings(AParent: PTyTreeNode);
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
    { Where Node's chrome slots and caption sit inside a cell whose left edge is
      ACellLeft. The thin accessor over TyTreeCaptionSlots: it supplies Indent,
      ShowRoot and the two per-node answers (does this node show a checkbox / does
      this tree have icons) so no caller has to restate them.

      ACellLeft IS THE ANCHOR AND IT IS THE CALLER'S ANSWER, deliberately. The two
      paints pass the main column's cell left; CellTextRect passes the cell rect it
      was given; GetNodeAtPoint passes the main column's cell left translated into
      its own content space (MainCellAnchor, which see) -- it used to pass a bare 0,
      assuming the main column starts at content x 0. That assumption is false
      whenever Header.MainColumn is not the leftmost visible column: the chrome then
      painted Scale(MainColumn.Left) px right of where the hit test looked for it,
      so the expander a user clicked answered hpLabel and the node never expanded.
      Every caller now names the same cell. }
    function  NodeCaptionSlots(Node: PTyTreeNode; ACellLeft, ACellRight, APPI: Integer;
                AIsMainColumn: Boolean): TTyTreeCaptionSlots;
    { The main column's cell left, expressed in GetNodeAtPoint's CONTENT space
      (x 0 = logical x 0, i.e. CR.Left + FOffsetX). That is Scale(MainColumn.Left)
      in multi-column mode and 0 in the 0-column tree, whose single cell is anchored
      at contentLeft by the paint. Derived from InternalCellRect -- the cell rect the
      PAINT fills -- so neither the geometry nor the "which column is the main one"
      policy (range check, coVisible, NoColumn -> MainColumn) exists twice.

      BOTH edges, because the slot walk needs the cell it is reflected in and not just
      the point it starts from. }
    procedure MainCellAnchor(const CR: TRect; APPI: Integer; out ALeft, ARight: Integer);
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
    { Virtual dispatch seams for the five events a subclass legitimately needs to
      IMPLEMENT rather than merely observe.

      Why they exist: TTyShellTreeView's constructor used to grab OnGetText, OnInitNode,
      OnExpanding, OnGetImageIndex and OnChange for its own handlers. Those five are
      PUBLISHED, so an application that assigned any of them silently replaced the shell
      behaviour -- the tree stopped showing filenames, or stopped populating on expand --
      with nothing to indicate that the two uses were fighting over one slot. LCL avoids
      it the same way: the shell behaviour lives in overridden virtuals and the events
      stay free for the app.

      Each default implementation fires the event, so an override that wants both calls
      inherited. }
    procedure DoGetText(Node: PTyTreeNode; var AText: string); virtual;
    procedure DoInitNode(AParent, Node: PTyTreeNode; var AStates: TTyNodeInitStates); virtual;
    procedure DoExpanding(Node: PTyTreeNode; var AAllowed: Boolean); virtual;
    procedure DoGetImageIndex(Node: PTyTreeNode; AKind: TTyVTImageKind; AColumn: Integer;
      var AGhosted: Boolean; var AIndex: Integer); virtual;
    procedure DoTreeChange(Node: PTyTreeNode); virtual;
    { LCL parity: the veto gate in front of every selection/focus move (LCL's
      CanChange, include/treeview.inc). Returns False when a handler cleared Allowed. }
    function  DoChanging(Node: PTyTreeNode): Boolean; virtual;
    { AutoExpand's open-the-new / close-the-old pair; no-op when AutoExpand is off. }
    procedure ApplyAutoExpand(APrev, ANew: PTyTreeNode);
    { A node's MAIN-column text, resolved exactly the way the caption is. Protected rather
      than private: "what does this node display" is a question a descendant legitimately
      asks (and the one a test asks to prove the caption path still reaches the app's
      OnGetText). Read-only, no side effects -- it never inits the node. }
    function  GetNodeSearchText(Node: PTyTreeNode): string;
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
    { ③f F2: the node-drag row-mode helper + the armed-but-not-yet-active source
      pointer. Protected so a descendant / test can drive/inspect the gesture
      internals (the ARM state, distinct from the public IsDraggingNode = active)
      without growing the public surface. }
    function  DropModeFromY(Target: PTyTreeNode; AY: Integer): TTyTreeDropMode;
    property  DragNode: PTyTreeNode read FDragNode;
    { ③f F3: force the active-drag state (source/target/mode) without driving the
      mouse gesture. Protected so a descendant / test can set up a drop-mark render
      in isolation — same rationale as DragNode/DropModeFromY above. No Invalidate
      (the caller paints explicitly). }
    procedure SetActiveDragState(ASource, ATarget: PTyTreeNode; AMode: TTyTreeDropMode);
    { --- 横轴镜像(RTL)-------------------------------------------------------

      本控件这一帧的横轴要不要镜像。**按类回答,不按实例**:默认跟着窗体的阅读方向
      (TControl.IsRightToLeft),后代在自己的 x 命中还没和绘制收口成一个来源之前
      覆写成 False。与 TTyListBox.RtlRowLayout / TTyCustomGrid.RtlLayout 同一条约定,
      `grep -n "RtlLayout"` 就是"谁镜像了"的诚实清单。
      TTyShellTreeView 不覆写:它只换了 DoGetText / DoInitNode / DoGetImageIndex,
      一个 x 也没有自己算。

      **BiDiMode 不 published** —— 见 tests/test.parity.pas 的
      LyingPropertiesStayUnpublished。 }
    function  RtlLayout: Boolean; virtual;
    { 本控件列轴的唯一描述(原点、密度、方向、反射带)。绘制的四处、命中的三处、
      拖列浮标全部从这里取 —— 于是"列往哪边排"在本控件里只存在一份答案。
      反射带是内容矩形 CR:padding 内缩、扣掉滚动条之后那一条,也就是列真正铺开的带。 }
    function  ColumnAxis(const CR: TRect; APPI: Integer): TTyColumnAxis;
    { 树线那条**手写 x 累加**的唯一出口。

      树线按**祖先**层级重算缩进,而槽位记录只覆盖本节点这一层 —— 所以它是本文件里
      最后一处没有被 TyTreeCaptionSlots 收进去的 x。镜像时它必须和槽位反射在同一个
      格子里、用同一条算术:节点镜像了而连线没有,连线就会横穿标题,比两边都不镜像更糟。
      三个调用点(祖先竖线、肘部竖线、肘部横段)全部走这里,于是"反射了两处漏了一处"
      在结构上不再可能。LTR 恒等。 }
    function  TreeLineX(ACellLeft, ACellRight, AX: Integer): Integer;
    function GetStyleTypeKey: string; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    { 流式化结束:.lfm 里的 Items 现在才物化(读期间条目是一条一条到的,
      每来一条就重建一次既慢又会在半棵树上算 Level),同时把读期间攒下的
      模式冲突抛出来 —— 在读期间抛会让报不报错取决于 .lfm 的属性顺序。 }
    procedure Loaded; override;
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
    { --- 条目模型的公开面(见单元中部 §条目模型)------------------------------
      IsItemMode:「这棵树现在的数据源是 Items 还是事件」——模式是推出来的
      (Items 非空),所以必须能被读出来,否则就成了只有控件自己知道的状态。
      NodeItem[]:记录节点 → 条目对象。虚拟模式下恒为 nil。
      NodeText[]:LCL `Node.Text` 的等价物。节点是**记录**不是类,挂不了成员,
      所以按本控件既有约定挂到控件上做带下标属性 —— 与 NodeSelected[] /
      NodeVisible[] 同一条命名规则(见 docs 第 7 节)。两种模式都答得出:
      条目模式取条目的 Text,虚拟模式走 OnGetTextWithType / OnGetText,
      也就是**屏幕上那一行真正显示的字**。只读:虚拟模式下没有可写的去处。 }
    { 这个后代能**不能**用条目模型(与 IsItemMode 的"现在是不是"是两个问题)。

      默认 True。**自己拥有数据源的后代必须覆写成 False** —— 判据是"有没有覆写
      DoGetText / 自己调 AddChild 建树"。TTyShellTreeView 正是这样一个:它的
      DoGetText 不调 inherited(标题来自文件系统),并且在 InitChildren 里自己
      AddChild 建子节点。给它填了 Items 的话,条目层会先按条目重建一棵树,
      然后它自己的填充代码撞上虚拟结构闸门抛异常 —— 响是响,但报的是 AddChild,
      指不到真正的原因。覆写成 False 之后,RebuildFromItems 当场用一句说得清的话
      拒绝,设计期的节点编辑器也不会挂到它上面。

      public 而不是 protected:设计期包要问这句话(决定给不给节点编辑动词),
      而它是个纯查询。

      本库里唯一覆写成 False 的是 TTyShellTreeView —— 它自己从文件系统建节点。 }
    function  SupportsItemModel: Boolean; virtual;
    property  IsItemMode: Boolean read FItemMode;
    { 一个节点占多少字节。本控件的卖点是"恒定内存下的百万节点",所以
      "一百万个节点要多少内存"必须是能问出来的 —— 而不是只能靠读代码推。
      同时它是那句承诺唯一的可断言形式:条目模式在块首征用 4 字节,虚拟模式
      一个字节都不多占,除此之外没有任何外部可观测量能区分这两件事
      (GetNodeData 的偏移恒为 TreeNodeSize,与分配步长无关)。 }
    property  NodeMemSize: Integer read FNodeAllocSize;
    property  NodeItem[Node: PTyTreeNode]: TTyTreeNodeItem read GetNodeItem;
    property  NodeText[Node: PTyTreeNode]: string read GetNodeText;
    procedure SetChildCount(Node: PTyTreeNode; NewCount: Cardinal);
    function  AddChild(AParent: PTyTreeNode): PTyTreeNode;
    procedure DeleteNode(Node: PTyTreeNode);
    procedure Clear;
    { ③f F1: pure intra-tree node-move engine. IsDescendant walks ANode.Parent up
      to the hidden root, returning True iff it passes through APossibleAncestor.
      CanMoveNode is the single validity gate (non-nil, AMode<>dmNone, ANode is not
      the hidden root, ANode<>ATarget, ATarget is NOT in ANode's subtree, and the
      move is not a no-op). MoveNode relinks the sibling lists, adjusts both parent
      chains' TotalCount/TotalHeight via the existing Adjust* spine, re-stamps the
      sibling Index on both lists, sets ANode.Parent, marks/auto-expands the new
      parent on dmOn, and InvalidateTreeLayout. No node is freed → cached pointers
      stay valid. Public — also usable programmatically. }
    function  IsDescendant(ANode, APossibleAncestor: PTyTreeNode): Boolean;
    function  CanMoveNode(ANode, ATarget: PTyTreeNode; AMode: TTyTreeDropMode): Boolean;
    function  MoveNode(ANode, ATarget: PTyTreeNode; AMode: TTyTreeDropMode): Boolean;
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
    { B2/B3 scroll engine.
      BREAKING (parity): this used to be called GetNodeAt. LCL's GetNodeAt is
      `GetNodeAt(X, Y: Integer): TTreeNode` (comctrls.pp:3716) — same name, same
      arity, both parameters Integer — so ported `n := Tree.GetNodeAt(X, Y)` BOUND to
      ours, read the caller's X as a scroll-space Y, returned the wrong node, and
      overwrote the caller's Y through the out parameter. Nothing warned. The LCL name
      now has the LCL meaning (below) and this one, which takes a scroll-space offset
      and answers with the row's absolute top, says so.
      Migration: GetNodeAt(y, top) -> GetNodeAtOffset(y, top). }
    function  GetNodeAtOffset(Y: Integer; out ANodeTop: Integer): PTyTreeNode;
    { LCL parity: the node under a CLIENT point, nil when the point is not on a node
      (comctrls.pp:3716). Thin wrapper over GetNodeAtPoint, which also reports which
      part of the row was hit. }
    function  GetNodeAt(X, Y: Integer): PTyTreeNode;
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
    { LCL parity: the last selected node in screen order (comctrls.pp:3737
      GetLastMultiSelected). A linear walk, like GetFirstSelected. }
    function  GetLastSelected: PTyTreeNode;
    { LCL parity: random access to the multi-selection, so the standard loop
        for i := 0 to Tree.SelectionCount - 1 do Use(Tree.Selections[i]);
      works without rewriting it as a pointer walk (comctrls.pp:3780/:3783).
      SelectionCount is Integer, not LCL's Cardinal, deliberately: with Cardinal that
      loop's `- 1` underflows to 4 billion on an empty selection.
      Selections[] is O(n) per call — for a hot loop over a large selection prefer
      GetFirstSelected/GetNextSelected. }
    property SelectionCount: Integer read SelectedCount;
    property Selections[AIndex: Integer]: PTyTreeNode read GetSelections;
    { C1: selection + focus }
    procedure ClearSelection;
    procedure FullExpand(Node: PTyTreeNode = nil);
    procedure FullCollapse(Node: PTyTreeNode = nil);
    procedure ScrollIntoView(Node: PTyTreeNode);
    property Expanded[Node: PTyTreeNode]: Boolean read GetExpanded write SetExpanded;
    { BREAKING (parity): this indexed Boolean used to be called Selected, which is the
      name LCL gives to THE current node (`property Selected: TTreeNode`,
      comctrls.pp:3778). `if Tree.Selected <> nil then ... ` and `Tree.Selected := N`
      — the two most-typed lines in TreeView code — could not compile against an
      indexed Boolean, and the error ("property requires an index") points nowhere
      near the real difference. The LCL name now carries the LCL meaning (below).
      Migration: Selected[N] -> NodeSelected[N]. }
    property NodeSelected[Node: PTyTreeNode]: Boolean read GetSelected write SetSelected;
    { LCL parity: the current node. Reading returns the focused node when it is
      selected (LCL's Selected is nil when nothing is selected); writing selects that
      node exclusively and moves focus to it, and nil clears the selection. }
    property Selected: PTyTreeNode read GetSelection write SetSelection;
    property FocusedNode: PTyTreeNode read GetFocusedNode write SetFocusedNode;
    { LCL parity: hide a single node and its subtree without deleting it — the shape
      a filter needs (comctrls.pp:3179). The walkers already honoured nsVisible; only
      the switch was missing, so filtering meant delete-and-re-add.
      NOT called Visible, deliberately. LCL puts it on TTreeNode, a class; our nodes
      are records, so it has to live on the control — where `Visible` already means
      "is this CONTROL on screen". An indexed property of that name would hide
      TControl.Visible and make `Tree.Visible := False` a compile error, which is the
      exact species of collision this pass exists to remove. Same NodeXxx convention
      as NodeSelected. }
    property NodeVisible[Node: PTyTreeNode]: Boolean read GetNodeVisible write SetNodeVisible;
    { LCL parity: re-askable "does this node have children" (comctrls.pp's
      OnHasChildren / NodeHasChildren). Ours was answered once, from OnInitNode's
      ivsHasChildren, and there was no public way to ask again — a directory that
      became non-empty could never grow an expander. Writing True marks the node
      expandable (children materialise lazily through OnInitChildren); writing False
      collapses it and drops the expander. }
    property HasChildren[Node: PTyTreeNode]: Boolean read GetHasChildren write SetHasChildren;
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
    { LCL parity: the scroll position, readable AND writable (comctrls.pp:3698-3699,
      :3787, :3759). Ours exposed OffsetX/OffsetY read-only, so save/restore across a
      refresh had to go through the scrollbar objects. ScrolledTop/ScrolledLeft are
      LCL's sign convention — positive pixels scrolled away — i.e. -OffsetY/-OffsetX.
      TopItem := N scrolls N to the top of the viewport. }
    property ScrolledTop:  Integer read GetScrolledTop  write SetScrolledTop;
    property ScrolledLeft: Integer read GetScrolledLeft write SetScrolledLeft;
    property TopItem:      PTyTreeNode read GetTopItem write SetTopItem;
    property BottomItem:   PTyTreeNode read GetBottomItem;
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
    { LCL parity: per-node geometry (comctrls.pp:3096-3102). GetCellRect answers the
      whole CELL; these answer the parts a custom overlay actually anchors to.
        DisplayRect(Node, TextOnly)  — the row rect, or just the caption's rect.
        DisplayTextLeft(Node)        — device X where the caption starts.
        DisplayExpandSignRect(Node)  — the expander's square (empty when it has none).
      All device px in ContentRect space, like GetCellRect, and all return False /
      an empty rect for a node that is not currently on screen — the same restriction
      GetCellRect has, since the geometry is derived from the paint walk. }
    function DisplayRect(Node: PTyTreeNode; TextOnly: Boolean; out ARect: TRect): Boolean;
    function DisplayTextLeft(Node: PTyTreeNode; out ALeft: Integer): Boolean;
    function DisplayExpandSignRect(Node: PTyTreeNode; out ARect: TRect): Boolean;
    { LCL parity: the node whose EXPANDER is under (X, Y), nil otherwise
      (comctrls.pp:3717 GetNodeWithExpandSignAt). }
    function GetNodeWithExpandSignAt(X, Y: Integer): PTyTreeNode;
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
    { LCL parity: the standard hit-test SET (comctrls.pp:3715, type at :41-43). Our own
      GetNodeAtPoint answers a single-valued enum, so "on the item AND on its label"
      could not be expressed and ported `if htOnButton in Tree.GetHitTestInfoAt(X,Y)`
      did not compile. Returns LCL's THitTests so it does. }
    function GetHitTestInfoAt(X, Y: Integer): THitTests;
    { E1: compare helper wrapping OnCompareNodes — returns 0 when unassigned }
    function DoCompare(Node1, Node2: PTyTreeNode; Column: Integer): Integer;
    { E1: sort the direct children of Node (one level only) }
    procedure Sort(Node: PTyTreeNode; Column: Integer; ADirection: TTySortDirection; DoInit: Boolean);
    { E2: recursive sort of the whole tree (initialized+expanded levels only) }
    procedure SortTree(Column: Integer; ADirection: TTySortDirection);
    { LCL parity: sort by the node's own text, with no compare handler at all
      (comctrls.pp:3709). Sort/SortTree route through DoCompare -> OnCompareNodes,
      which returns 0 when the handler is unassigned — so "sort this tree
      alphabetically", the single most common ask, was a silent no-op. AlphaSort
      compares the MAIN-column text the painter shows (GetNodeSearchText), case-
      insensitively, and needs no handler. Node = nil sorts the whole tree. }
    function AlphaSort(Node: PTyTreeNode = nil): Boolean;
    { LCL parity: sort with a plain FUNCTION rather than a method-pointer event
      (comctrls.pp:3712/:2965). OnCompareNodes is restored afterwards. }
    function CustomSort(SortProc: TTyTreeNodeCompare; Node: PTyTreeNode = nil): Boolean;
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
    { ③f F2: end any in-progress node drag — clear all drag state + Invalidate.
      Safe to call when not dragging (no-op-ish: just re-clears + repaints). Called
      on MouseUp commit, Esc, teardown (DeleteNode/Clear), and option-off. }
    procedure EndNodeDrag;
    { ③f F2: read-only node-drag state. }
    property IsDraggingNode: Boolean         read FDragActive;
    property DropTargetNode: PTyTreeNode     read FDropTarget;
    property DropMode:       TTyTreeDropMode read FDropMode;
    { LCL names for four switches that were only reachable as Options set members or
      under a different spelling (comctrls.pp:3697/:3662/:3701/:3694). Public rather
      than published on purpose: Options and ShowTreeLines already stream, and a
      second storable copy of the same bit would let a .lfm contradict itself.
      NOTE ReadOnly's default. LCL's is False (editing on out of the box); ours is
      True, because editing here is opt-in through toEditable and every shipped tree
      relies on that. ReadOnly := False is exactly Options + [toEditable]. }
    property RowSelect:   Boolean read GetRowSelect   write SetRowSelect;
    property MultiSelect: Boolean read GetMultiSelect write SetMultiSelect;
    property ShowLines:   Boolean read GetShowLines   write SetShowLines;
    property ReadOnly:    Boolean read GetReadOnly    write SetReadOnly;
    { LCL parity: DefaultItemHeight is LCL's name for what we call DefaultNodeHeight
      (comctrls.pp:3761). Same storage, same stored-sentinel behaviour — public, not
      published, so only one of the two names streams. }
    property DefaultItemHeight: Integer read GetDefaultNodeHeight write SetDefaultNodeHeight;
  published
    { B1: option flags set (default [] = ③a/③b behaviour) }
    property Options: TTyTreeOptions read FOptions write SetOptions default [];
    { B (columns): header sub-object }
    property Header: TTyHeader read FHeader write SetHeader;
    { 设计期 / .lfm 里的节点树(见单元中部 §条目模型)。非空 = 条目模式。
      **setter 必须在**,哪怕读者从不调用它:FPC 的 TWriter.WriteProperty 对
      没有 setter 的属性直接返回(设计器于是静默不保存),TReader.ReadPropValue
      在看属性种类之前就抛 EReadError。本库两天前刚在 TTyHeader.Columns 上
      栽过这一次(7d2c03d)。 }
    property Items: TTyTreeNodes read FItems write SetItems;
    property NodeDataSize: Integer read FNodeDataSize write SetNodeDataSize default -1;
    { Default node/row height in logical px. Left unset it follows the theme's
      --item-height token, so nodes get denser rows at classic density (18) and
      roomier ones at modern density (38) automatically. Set it explicitly and that
      value wins and is streamed (stored FDefaultNodeHeightExplicit). }
    property DefaultNodeHeight: Integer read GetDefaultNodeHeight write SetDefaultNodeHeight stored FDefaultNodeHeightExplicit;
    property RootNodeCount: Cardinal read GetRootNodeCount write SetRootNodeCount default 0;
    { C1: display properties }
    property Indent: Integer read FIndent write SetIndent default 16;
    property Images: TCustomImageList read FImages write SetImages;
    property EmptyListMessage: string read FEmptyListMessage write FEmptyListMessage;
    property ShowButtons: Boolean read FShowButtons write SetShowButtons default True;
    property ShowTreeLines: Boolean read FShowTreeLines write SetShowTreeLines default True;
    property ShowRoot: Boolean read FShowRoot write SetShowRoot default True;
    property ToggleOnDblClick: Boolean read FToggleOnDblClick write SetToggleOnDblClick default True;
    property HotTrack: Boolean read FHotTrack write SetHotTrack default False;
    { LCL parity switches — see the field declarations for the LCL line numbers and for
      why RightClickSelect defaults True here where LCL defaults False. }
    property ScrollBars: TScrollStyle read FScrollBars write SetScrollBars default ssBoth;
    property AutoExpand: Boolean read FAutoExpand write FAutoExpand default False;
    property RightClickSelect: Boolean read FRightClickSelect write FRightClickSelect default True;
    property HideSelection: Boolean read FHideSelection write SetHideSelection default True;
    property ShowSeparators: Boolean read FShowSeparators write SetShowSeparators default False;
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
    { LCL parity: fires BEFORE the selection moves; clear Allowed to keep the user
      where they are (comctrls.pp:3669). }
    property OnChanging:      TTyTreeChangingEvent     read FOnChanging      write FOnChanging;
    property OnFocusChanged:  TTyTreeNodeEvent         read FOnFocusChanged  write FOnFocusChanged;
    { C1: check events }
    property OnChecking: TTyTreeCheckingEvent          read FOnChecking      write FOnChecking;
    property OnChecked:  TTyTreeNodeEvent              read FOnChecked       write FOnChecked;
    { D1: selection-changed event — fired once per gesture when multi-select set changes }
    property OnSelectionChanged: TNotifyEvent          read FOnSelectionChanged write FOnSelectionChanged;
    property OnNodeClick:     TTyTreeNodeEvent         read FOnNodeClick     write FOnNodeClick;
    property OnNodeDblClick:  TTyTreeNodeEvent         read FOnNodeDblClick  write FOnNodeDblClick;
    { C3: paint events }
    { 两个 setter 不是装饰:它们是条目模式的冲突闸门之一(另一半在
      RebuildFromItems)。Items 非空时再挂标题事件 = 标题有两个主人,抛异常。 }
    property OnGetText:            TTyTreeGetTextEvent           read FOnGetText            write SetOnGetText;
    property OnGetTextWithType:    TTyTreeGetTextWithTypeEvent   read FOnGetTextWithType    write SetOnGetTextWithType;
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
    { LCL parity: one event for "the editor closed", commit or cancel }
    property OnEditingEnd:    TTyTreeEditingEndEvent read FOnEditingEnd    write FOnEditingEnd;
    { ③f F2: intra-tree node-drag events. OnNodeDragOver was called OnDragOver until
      it was moved off the name TControl already owns — see TTyTreeDragOverEvent. }
    property OnNodeDragOver:  TTyTreeDragOverEvent   read FOnDragOver      write FOnDragOver;
    property OnNodeMoved:     TTyTreeNodeEvent       read FOnNodeMoved     write FOnNodeMoved;
    { The LCL drag-and-drop surface the base class publishes. Re-listed here only so
      the tree's own published block shows it is back — TTyTreeDragOverEvent used to
      shadow OnDragOver, which made this the one TTy control that could not be an LCL
      drop target. }
    property OnDragOver;
    property OnDragDrop;
    property OnStartDrag;
    property OnEndDrag;
    property DragMode;
    property DragCursor;
  end;

{ ---------------------------------------------------------------------------
  The ONE place a node's caption x is worked out.
  --------------------------------------------------------------------------- }

{ Lay out one cell's chrome slots in reading order, across [ACellLeft, ACellRight).

  Pure on purpose: it takes the two control settings it needs (Indent, ShowRoot)
  and the two per-node answers (has a checkbox / has an image) as plain arguments,
  so it can be reasoned about and tested without a tree, and so that every caller
  is forced to state WHICH cell it is laying out. That last part matters: the
  callers did not always agree on the answer -- see NodeCaptionSlots.

  APPI scales; 96 is the identity. AIsMainColumn = False short-circuits to a bare
  text pad, which is what a non-main cell has always drawn.

  ARightToLeft REFLECTS the finished walk inside the cell rather than re-tiling it
  backwards from ACellRight. Same reason as TyColumnSpan and TyHeaderSectionRects: the
  widths, the scaling and the "is this slot present at all" decisions are made once, above,
  and a reflection cannot round or re-decide any of them. A reverse accumulation would be a
  second copy of the walk, and the first time a slot was added only one copy would get it.
  It is also the only version under which a mirrored cell provably has no gap the
  unmirrored one lacked. LTR leaves every field byte-identical to before. }
function TyTreeCaptionSlots(ACellLeft, ACellRight, APPI, AIndent, ALevel: Integer;
  AShowRoot, AHasCheckBox, AHasImage, AIsMainColumn, ARightToLeft: Boolean): TTyTreeCaptionSlots;

implementation

{ ===========================================================================
  TTyTreeNodeItem —— 一个条目

  所有结构问题(父、子、子树大小)都由**扁平序 + Level** 现算,条目自己不存
  任何指针。这样 .lfm 里手写一串 Level 与用 AddChild 建出来的树是同一个东西,
  不存在"指针对了但 Level 没跟上"这种第二真相。
  =========================================================================== }

constructor TTyTreeNodeItem.Create(ACollection: TCollection);
begin
  inherited Create(ACollection);
  FImageIndex    := -1;
  FSelectedIndex := -1;
  FLevel         := 0;
  FCheckType     := ctNone;
  FCheckState    := csUnchecked;
end;

procedure TTyTreeNodeItem.Assign(ASource: TPersistent);
var
  src: TTyTreeNodeItem;
begin
  if ASource is TTyTreeNodeItem then
  begin
    src := TTyTreeNodeItem(ASource);
    FText          := src.FText;
    FLevel         := src.FLevel;
    FImageIndex    := src.FImageIndex;
    FSelectedIndex := src.FSelectedIndex;
    FExpanded      := src.FExpanded;
    FCheckType     := src.FCheckType;
    FCheckState    := src.FCheckState;
    FData          := src.FData;
    { Assign 会搬 Level,所以是结构变更。 }
    Changed(True);
  end
  else
    inherited Assign(ASource);
end;

function TTyTreeNodeItem.GetTreeNodes: TTyTreeNodes;
begin
  if Collection is TTyTreeNodes then
    Result := TTyTreeNodes(Collection)
  else
    Result := nil;
end;

{ 对象查看器集合编辑器左边那一列。带上缩进,于是那个通用编辑器里也能一眼看出树形
  —— 这是"扁平集合 + Level"这个形状白拿的好处。 }
function TTyTreeNodeItem.GetDisplayName: string;
begin
  if FText <> '' then
    Result := StringOfChar(' ', 2 * FLevel) + FText
  else
    Result := inherited GetDisplayName;
end;

procedure TTyTreeNodeItem.SetText(const AValue: TCaption);
begin
  if FText = AValue then Exit;
  FText := AValue;
  Changed(False);
end;

{ Level 是树形本身,所以它是**结构**变更(Changed(True) → Update(nil) → 整棵重建)。

  这里**不**夹紧。规范化("首项是 0,其余至多比前一项深 1 层")只在
  RebuildFromItems 里做一次,并写回 FLevel —— 一处规范化,一个真相。
  两处都夹的第一版反而更弱:物化那次写回会把 setter 的结果盖掉,于是删掉
  setter 里的夹紧,测试照样全绿(变异体 M11 存活)。真正兜底的一直是物化那一处,
  而它才是 .lfm 手写、InsertAt 直写字段、Assign 搬运三条路的共同必经之地。 }
procedure TTyTreeNodeItem.SetLevel(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FLevel = AValue then Exit;
  FLevel := AValue;
  Changed(True);
end;

procedure TTyTreeNodeItem.SetImageIndex(AValue: Integer);
begin
  if FImageIndex = AValue then Exit;
  FImageIndex := AValue;
  Changed(False);
end;

procedure TTyTreeNodeItem.SetSelectedIndex(AValue: Integer);
begin
  if FSelectedIndex = AValue then Exit;
  FSelectedIndex := AValue;
  Changed(False);
end;

procedure TTyTreeNodeItem.SetExpanded(AValue: Boolean);
begin
  if FExpanded = AValue then Exit;
  FExpanded := AValue;
  Changed(False);
end;

procedure TTyTreeNodeItem.SetCheckType(AValue: TTyCheckType);
begin
  if FCheckType = AValue then Exit;
  FCheckType := AValue;
  Changed(False);
end;

procedure TTyTreeNodeItem.SetCheckState(AValue: TTyCheckState);
begin
  if FCheckState = AValue then Exit;
  FCheckState := AValue;
  Changed(False);
end;

{ 父 = 往前找第一个 Level 更小的条目。 }
function TTyTreeNodeItem.Parent: TTyTreeNodeItem;
var
  i: Integer;
begin
  Result := nil;
  if (Collection = nil) or (FLevel = 0) then Exit;
  for i := Index - 1 downto 0 do
    if TTyTreeNodeItem(Collection.Items[i]).FLevel < FLevel then
      Exit(TTyTreeNodeItem(Collection.Items[i]));
end;

{ 子树 = 紧跟其后、Level 一直更深的那一段。 }
function TTyTreeNodeItem.SubTreeCount: Integer;
var
  i: Integer;
begin
  Result := 1;
  if Collection = nil then Exit;
  for i := Index + 1 to Collection.Count - 1 do
  begin
    if TTyTreeNodeItem(Collection.Items[i]).FLevel <= FLevel then Break;
    Inc(Result);
  end;
end;

function TTyTreeNodeItem.Count: Integer;
var
  i: Integer;
begin
  Result := 0;
  if Collection = nil then Exit;
  for i := Index + 1 to Collection.Count - 1 do
  begin
    if TTyTreeNodeItem(Collection.Items[i]).FLevel <= FLevel then Break;
    if TTyTreeNodeItem(Collection.Items[i]).FLevel = FLevel + 1 then Inc(Result);
  end;
end;

function TTyTreeNodeItem.Items(AIndex: Integer): TTyTreeNodeItem;
var
  i, n: Integer;
begin
  Result := nil;
  if (Collection = nil) or (AIndex < 0) then Exit;
  n := 0;
  for i := Index + 1 to Collection.Count - 1 do
  begin
    if TTyTreeNodeItem(Collection.Items[i]).FLevel <= FLevel then Break;
    if TTyTreeNodeItem(Collection.Items[i]).FLevel = FLevel + 1 then
    begin
      if n = AIndex then Exit(TTyTreeNodeItem(Collection.Items[i]));
      Inc(n);
    end;
  end;
end;

function TTyTreeNodeItem.HasChildren: Boolean;
begin
  Result := (Collection <> nil) and (Index + 1 < Collection.Count)
        and (TTyTreeNodeItem(Collection.Items[Index + 1]).FLevel > FLevel);
end;

{ ===========================================================================
  TTyTreeNodes —— 条目集合(顺序 = 前序)
  =========================================================================== }

constructor TTyTreeNodes.Create(AOwner: TPersistent);
begin
  inherited Create(TTyTreeNodeItem);
  FOwner := AOwner;
end;

function TTyTreeNodes.GetOwner: TPersistent;
begin
  Result := FOwner;
end;

function TTyTreeNodes.GetItem(AIndex: Integer): TTyTreeNodeItem;
begin
  Result := TTyTreeNodeItem(inherited Items[AIndex]);
end;

procedure TTyTreeNodes.SetItem(AIndex: Integer; AValue: TTyTreeNodeItem);
begin
  inherited Items[AIndex] := AValue;
end;

function TTyTreeNodes.GetTopLvlCount: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to Count - 1 do
    if GetItem(i).Level = 0 then Inc(Result);
end;

function TTyTreeNodes.GetTopLvlItems(AIndex: Integer): TTyTreeNodeItem;
var
  i, n: Integer;
begin
  Result := nil;
  if AIndex < 0 then Exit;
  n := 0;
  for i := 0 to Count - 1 do
    if GetItem(i).Level = 0 then
    begin
      if n = AIndex then Exit(GetItem(i));
      Inc(n);
    end;
end;

function TTyTreeNodes.GetFirstNode: TTyTreeNodeItem;
begin
  if Count = 0 then Result := nil else Result := GetItem(0);
end;

procedure TTyTreeNodes.Notify(Item: TCollectionItem; Action: TCollectionNotification);
begin
  inherited Notify(Item, Action);
  { 增 / 删都改树形。cnAdded 之后 TCollection 还会走 Changed → Update,
    这里只把"这一批是结构变更"记下来。 }
  if Action in [cnAdded, cnExtracting, cnDeleting] then
    FStructural := True;
end;

procedure TTyTreeNodes.Update(Item: TCollectionItem);
begin
  inherited Update(Item);
  if not (FOwner is TTyTreeView) then Exit;
  if FStructural or (Item = nil) then
  begin
    FStructural := False;
    TTyTreeView(FOwner).ItemsStructureChanged;
  end
  else
    TTyTreeView(FOwner).ItemStateChanged(TTyTreeNodeItem(Item));
end;

{ 唯一的建条目出口:在 AIndex 处插入,Level 由调用者算好。
  五个 LCL 形状的 Add* 全部落到这里,于是"插到哪、几层"只有一处算术。 }
function TTyTreeNodes.InsertAt(AIndex, ALevel: Integer; const S: string): TTyTreeNodeItem;
begin
  BeginUpdate;
  try
    Result := TTyTreeNodeItem(inherited Add);
    if AIndex < Result.Index then Result.Index := AIndex;
    { 直接写字段:SetLevel 会按"前一项"夹紧,而这里的落点是算准的,
      在插入的瞬间前一项可能还没就位。 }
    Result.FLevel := ALevel;
    Result.FText  := S;
    FStructural := True;
  finally
    EndUpdate;
  end;
end;

{ LCL: Add(Sibling, S) = 加成 Sibling 的**最后一个**兄弟。Sibling=nil → 顶层末尾。 }
function TTyTreeNodes.Add(ASibling: TTyTreeNodeItem; const S: string): TTyTreeNodeItem;
var
  parent: TTyTreeNodeItem;
begin
  if ASibling = nil then
    Result := InsertAt(Count, 0, S)
  else
  begin
    parent := ASibling.Parent;
    if parent = nil then
      Result := InsertAt(Count, 0, S)
    else
      Result := InsertAt(parent.Index + parent.SubTreeCount, ASibling.Level, S);
  end;
end;

function TTyTreeNodes.AddFirst(ASibling: TTyTreeNodeItem; const S: string): TTyTreeNodeItem;
var
  parent: TTyTreeNodeItem;
begin
  if ASibling = nil then
    Result := InsertAt(0, 0, S)
  else
  begin
    parent := ASibling.Parent;
    if parent = nil then
      Result := InsertAt(0, 0, S)
    else
      Result := InsertAt(parent.Index + 1, parent.Level + 1, S);
  end;
end;

{ **移植过来的那一行**:Tree.Items.AddChild(nil, 'Root')。
  加成 AParent 的最后一个子条目 = 插在 AParent 子树的末尾。 }
function TTyTreeNodes.AddChild(AParent: TTyTreeNodeItem; const S: string): TTyTreeNodeItem;
begin
  if AParent = nil then
    Result := InsertAt(Count, 0, S)
  else
    Result := InsertAt(AParent.Index + AParent.SubTreeCount, AParent.Level + 1, S);
end;

function TTyTreeNodes.AddChildFirst(AParent: TTyTreeNodeItem; const S: string): TTyTreeNodeItem;
begin
  if AParent = nil then
    Result := InsertAt(0, 0, S)
  else
    Result := InsertAt(AParent.Index + 1, AParent.Level + 1, S);
end;

{ LCL: Insert(Sibling, S) = 插在 Sibling **之前**。 }
function TTyTreeNodes.Insert(ASibling: TTyTreeNodeItem; const S: string): TTyTreeNodeItem;
begin
  if ASibling = nil then
    Result := InsertAt(Count, 0, S)
  else
    Result := InsertAt(ASibling.Index, ASibling.Level, S);
end;

{ 删子树。只 Delete(i) 会让子条目变孤儿:它们的 Level 突然比前一项深 2 层,
  下一次物化时会被夹紧成别人的孩子 —— 树默默换了形状,比报错难查得多。 }
procedure TTyTreeNodes.DeleteItem(AItem: TTyTreeNodeItem);
var
  i, first, n: Integer;
begin
  if (AItem = nil) or (AItem.Collection <> Self) then Exit;
  first := AItem.Index;
  n     := AItem.SubTreeCount;
  BeginUpdate;
  try
    for i := 1 to n do
      Delete(first);
    FStructural := True;
  finally
    EndUpdate;
  end;
end;

{ TTyTreeView }

{ Reflect one x INSIDE a cell. It reflects the PIXEL [AX, AX+1), not the boundary at AX,
  which is the difference between a mirrored line landing on the column of pixels it was
  drawn in and landing half a pixel off it -- the classic "painted here, answers there". }
function TyTreeMirrorX(AX, ACellLeft, ACellRight: Integer): Integer;
begin
  Result := BidiFlipRect(Rect(AX, 0, AX + 1, 0),
                         Rect(ACellLeft, 0, ACellRight, 0), True).Left;
end;

function TyTreeCaptionSlots(ACellLeft, ACellRight, APPI, AIndent, ALevel: Integer;
  AShowRoot, AHasCheckBox, AHasImage, AIsMainColumn, ARightToLeft: Boolean): TTyTreeCaptionSlots;

  { Reflect a [X, X+W) slot about the cell and return its new LEFT. Width is invariant,
    which is exactly why the fields can stay physical-left and every consumer's [X, X+W)
    keeps working. }
  function Flip(AX, AW: Integer): Integer;
  begin
    Result := BidiFlipRect(Rect(AX, 0, AX + AW, 0),
                           Rect(ACellLeft, 0, ACellRight, 0), True).Left;
  end;

begin
  FillChar(Result, SizeOf(Result), 0);
  Result.RightToLeft := ARightToLeft;
  if not AIsMainColumn then
  begin
    { A non-main cell carries no indent, no expander, no checkbox and no icon --
      only the flat margin the painter has always used (colMargin = Scale(4)).
      It is symmetric, so mirroring leaves it alone; the caption INSIDE it still changes
      sides, but that is the painter's alignment lever, not this walk's business. }
    Result.CaptionX     := ACellLeft;
    Result.CaptionRight := ACellRight;
    Result.TextPad      := MulDiv(4, APPI, 96);
    Exit;
  end;

  Result.IndentPx    := MulDiv((ALevel + Ord(AShowRoot)) * AIndent, APPI, 96);
  { The expander occupies the Indent-wide slot that ENDS at IndentPx, so it is
    drawn inside the indent the node has already earned rather than pushing the
    caption further along at every level. }
  Result.ButtonSlotW := MulDiv(AIndent, APPI, 96);
  Result.ButtonSlotX := ACellLeft + Result.IndentPx - Result.ButtonSlotW;

  { CaptionX walks past each slot that is actually present. This walk is the
    thing that used to be copied out four times; a slot's width is 0 exactly when
    it is absent, which is also how a consumer tells whether CheckX/ImageX mean
    anything. }
  Result.CaptionX := ACellLeft + Result.IndentPx;
  if AHasCheckBox then
  begin
    Result.CheckW := MulDiv(16, APPI, 96);
    Result.CheckX := Result.CaptionX;
    Inc(Result.CaptionX, Result.CheckW);
  end;
  if AHasImage then
  begin
    Result.ImageW := MulDiv(AIndent, APPI, 96);
    Result.ImageX := Result.CaptionX;
    Inc(Result.CaptionX, Result.ImageW);
  end;
  Result.CaptionRight := ACellRight;
  Result.TextPad      := MulDiv(2, APPI, 96);

  if not ARightToLeft then Exit;
  { One reflection, applied to every slot including the caption remainder. Reflecting the
    caption as a RECTANGLE rather than reflecting its two edges separately is what keeps
    it from coming out inverted when the chrome fills most of a narrow cell. }
  Result.ButtonSlotX := Flip(Result.ButtonSlotX, Result.ButtonSlotW);
  if Result.CheckW > 0 then Result.CheckX := Flip(Result.CheckX, Result.CheckW);
  if Result.ImageW > 0 then Result.ImageX := Flip(Result.ImageX, Result.ImageW);
  ACellLeft := Flip(Result.CaptionX, Result.CaptionRight - Result.CaptionX);
  Result.CaptionRight := ACellLeft + (Result.CaptionRight - Result.CaptionX);
  Result.CaptionX     := ACellLeft;
end;

function TTyTreeView.GetStyleTypeKey: string;
begin
  Result := 'TyTreeView';
end;

function TTyTreeView.RtlLayout: Boolean;
begin
  Result := IsRightToLeft;
end;

function TTyTreeView.ColumnAxis(const CR: TRect; APPI: Integer): TTyColumnAxis;
begin
  { CR.Left + FOffsetX is this control's content origin -- FOffsetX is <= 0 here, so it is
    ADDED; the list view stores the same quantity >= 0 and subtracts. Both mean "where
    logical x 0 currently sits", which is exactly what an origin is. }
  Result := TyColumnAxis(CR.Left + FOffsetX, APPI, RtlLayout, CR.Left, CR.Right);
end;

function TTyTreeView.TreeLineX(ACellLeft, ACellRight, AX: Integer): Integer;
begin
  if not RtlLayout then Exit(AX);
  Result := TyTreeMirrorX(AX, ACellLeft, ACellRight);
end;

procedure TTyTreeView.KeyStepIn(Node: PTyTreeNode);
{ Deeper: expand a collapsed node, else descend to its first child. }
var
  nxt: PTyTreeNode;
begin
  if Node = nil then Exit;
  InitNode(Node);
  if (nsHasChildren in Node^.States) and not (nsExpanded in Node^.States) then
  begin
    Expanded[Node] := True;
    Exit;
  end;
  { Already expanded or no children: move to first child }
  nxt := GetNextVisibleNoInit(Node);
  if (nxt <> nil) and (nxt^.Parent = Node) then
  begin
    FocusedNode := nxt;
    ScrollIntoView(nxt);
  end;
end;

procedure TTyTreeView.KeyStepOut(Node: PTyTreeNode);
{ Shallower: collapse an expanded node, else climb to its parent. }
var
  nxt: PTyTreeNode;
begin
  if Node = nil then Exit;
  if nsExpanded in Node^.States then
  begin
    Expanded[Node] := False;
    Exit;
  end;
  nxt := GetParent(Node);
  if nxt <> nil then
  begin
    FocusedNode := nxt;
    ScrollIntoView(nxt);
  end;
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
    { LCL parity: the veto runs BEFORE anything moves (comctrls.pp:3669 / CanChange).
      Placed after the no-op early-out so a handler is not asked about a change that
      is not happening. }
    if not DoChanging(Node) then Exit;
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

  if didChange then
    DoTreeChange(Node);
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
    DoTreeChange(prev)
  else
    DoTreeChange(nil);
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
  { LCL parity: OnChanging vetoes the whole move — focus does NOT budge either, or
    the caret and the selection would end up on different rows. }
  if not DoChanging(AValue) then Exit;
  prevFocus   := FFocusedNode;
  FFocusedNode := AValue;
  // Focusing selects in single-select mode.
  if AValue <> nil then
  begin
    { one OnChanging per gesture: the question was already asked above }
    FSuppressChanging := True;
    try
      SetSelected(AValue, True);
    finally
      FSuppressChanging := False;
    end;
  end;
  if Assigned(FOnFocusChanged) then
    FOnFocusChanged(Self, AValue);
  { AutoExpand runs after the notification, so a handler reading Expanded[] sees the
    state the user is about to see. }
  ApplyAutoExpand(prevFocus, AValue);
  Invalidate;
end;

{ MoveFocusOnly — move keyboard focus without touching the selection set.
  Used by the multi-select mouse/keyboard paths to position the caret
  independently of selection. }
procedure TTyTreeView.MoveFocusOnly(AValue: PTyTreeNode);
var
  prevFocus: PTyTreeNode;
begin
  if AValue = FFocusedNode then Exit;
  if not DoChanging(AValue) then Exit;
  prevFocus    := FFocusedNode;
  FFocusedNode := AValue;
  if Assigned(FOnFocusChanged) then FOnFocusChanged(Self, AValue);
  ApplyAutoExpand(prevFocus, AValue);
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
  else
    DoGetText(Node, Result);
end;

{ NodeMatchesSearch — the match predicate for one candidate node.
  Default (OnIncrementalSearch unassigned) = case-insensitive PREFIX test of
  ASearchText against the node's main-column text (both upper-cased via
  UTF8UpperCase so multibyte casing is correct). When OnIncrementalSearch is
  assigned the app fully decides (AMatch seeded False). }
function TTyTreeView.NodeMatchesSearch(Node: PTyTreeNode; const ASearchText: string): Boolean;
var
  { 局部名不能再叫 nodeText:控件上现在有带下标属性 NodeText[]（LCL Node.Text
    的等价物），Pascal 不区分大小写，同名局部会把它遮掉。 }
  nodeTxt, upSearch: string;
begin
  Result := False;
  if (Node = nil) or (Node = FRoot) or (ASearchText = '') then Exit;
  if Assigned(FOnIncrementalSearch) then
  begin
    FOnIncrementalSearch(Self, Node, ASearchText, Result);
    Exit;
  end;
  { Default: case-insensitive prefix match on the main-column caption. }
  nodeTxt  := UTF8UpperCase(GetNodeSearchText(Node));
  upSearch := UTF8UpperCase(ASearchText);
  Result := (upSearch <> '')
            and (UTF8Length(nodeTxt) >= UTF8Length(upSearch))
            and (UTF8Copy(nodeTxt, 1, UTF8Length(upSearch)) = upSearch);
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

procedure TTyTreeView.SetImages(AValue: TCustomImageList);
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
  { ③f F2: toNodeDrag turned off mid-drag ⇒ abandon the drag (no move). Idempotent
    when not dragging. }
  if FDragActive and not (toNodeDrag in AValue) then EndNodeDrag;
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
  SBThick := MulDiv(ActiveController.Metric('--scrollbar-size', TyScrollbarSize), PPI, 96);
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
  SBThick := MulDiv(ActiveController.Metric('--scrollbar-size', TyScrollbarSize), PPI, 96);

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

  { LCL parity: ScrollBars gates which axes may have a bar at all (comctrls.pp:3777).
    Applied AFTER the content-extent decision so the "does it fit" maths above is
    untouched -- this only removes a bar the property forbids, and the width/height
    it was going to steal is given back so the content uses the full viewport.
    ssAuto* behave like their plain counterparts here: our bars are already auto
    (they appear only when the content overflows), so ssAutoBoth == ssBoth. }
  if not (FScrollBars in [ssVertical, ssBoth, ssAutoVertical, ssAutoBoth]) then
  begin
    if wantVScroll then viewW := viewW + SBThick;
    wantVScroll := False;
  end;
  if not (FScrollBars in [ssHorizontal, ssBoth, ssAutoHorizontal, ssAutoBoth]) then
  begin
    if wantHScroll then viewH := viewH + MulDiv(SBThick, 96, PPI);
    wantHScroll := False;
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
    { A mirrored tree scrolls from the RIGHT: Position = Min shows the reading start, which
      is now the right-hand end of the content. The bar has to be told, because
      MirrorHorizontal is opt-in and deliberately NOT wired to BiDiMode -- a bar must never
      mirror ahead of the content it scrolls, and until this commit this one's content did
      not. Same call TTyCustomGrid makes for the same reason. }
    FHScroll.MirrorHorizontal := RtlLayout;
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
  step := 3 * GetDefaultNodeHeight;
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

procedure TTyTreeView.SetHeader(AValue: TTyHeader);
begin
  FHeader.Assign(AValue);
end;

constructor TTyTreeView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FNodeDataSize := -1;
  FNodeAllocSize := TreeNodeSize;
  { 条目集合总是存在(空 = 虚拟模式);published 的子对象属性不能是 nil。 }
  FItems := TTyTreeNodes.Create(Self);
  FItemMode := False;
  FDefaultNodeHeight := 18;              // classic fallback; unused while FDefaultNodeHeightExplicit=False
  FDefaultNodeHeightExplicit := False;   // follow --item-height (density-aware) until pinned
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
  { ③f F2: node-drag — idle state }
  FDragNode         := nil;
  FDragActive       := False;
  FDragStartPos     := Point(0, 0);
  FDropTarget       := nil;
  FDropMode         := dmNone;
  { LCL parity defaults. ssBoth / False / True / False match LCL; RightClickSelect
    is True because that is what this control has always done on right-down. }
  FScrollBars       := ssBoth;
  FAutoExpand       := False;
  FRightClickSelect := True;
  FHideSelection    := True;
  FShowSeparators   := False;
  { TabStop=False on both: a standalone TTyScrollBar is focusable (it owns arrow/page keys),
    but a bar embedded in the tree must not be — dragging it would take focus off the tree,
    which would then lose its focus ring and its keyboard navigation mid-scroll. }
  FVScroll := TTyScrollBar.Create(Self);
  FVScroll.Parent            := Self;
  FVScroll.Kind              := sbVertical;
  FVScroll.TabStop           := False;
  FVScroll.AnimationsEnabled := False;
  FVScroll.OnChange          := @VScrollChange;
  FVScroll.Visible           := False;
  FVScroll.ControlStyle      := FVScroll.ControlStyle + [csNoDesignVisible];   // internal: never shown as a designable child (runtime shows it via UpdateScrollBars)
  FHScroll := TTyScrollBar.Create(Self);
  FHScroll.Parent            := Self;
  FHScroll.Kind              := sbHorizontal;
  FHScroll.TabStop           := False;
  FHScroll.AnimationsEnabled := False;
  FHScroll.OnChange          := @HScrollChange;
  FHScroll.Visible           := False;
  FHScroll.ControlStyle      := FHScroll.ControlStyle + [csNoDesignVisible];   // internal: hide in the designer
  { B (columns): create the header sub-object and wire its change notification }
  FHeader := TTyHeader.Create;
  FHeader.OnChange := @HeaderChanged;
  { ③e E1: the persistent inline editor — hidden, non-tab-stop, parented to the
    tree so it shares the tree's Controller (themed automatically) and lives in
    the same client coordinate space the cell rects use. Shown + positioned on
    demand by EditNode (E2); dormant while toEditable is off. }
  FEditor := TTyEdit.Create(Self);
  FEditor.Parent  := Self;
  FEditor.Visible := False;
  FEditor.TabStop := False;
  FEditor.ControlStyle := FEditor.ControlStyle + [csNoDesignVisible];   // internal inline editor: hide in the designer (EditNode shows it at runtime)
  { ③e E4: editor input — Enter commits, Esc cancels (EditorKeyDown), and losing
    focus commits Explorer-style (EditorExit). }
  FEditor.OnKeyDown := @EditorKeyDown;
  FEditor.OnExit    := @EditorExit;
  TabStop           := True;
  Width := 200; Height := 160;
end;

destructor TTyTreeView.Destroy;
begin
  { 拆控件时条目层先退场:此后 Clear / DeleteNode 走的是纯虚拟路径,
    不会再回流到条目层去重建一棵正在被销毁的树。两个赋值必须在
    FItems.Free 之前 —— 释放集合会触发 Notify。 }
  FItemMode        := False;
  FRebuildingItems := True;
  FreeAndNil(FItems);
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
  Result^.NodeHeight := GetDefaultNodeHeight;
  // TotalCount and TotalHeight for a fresh leaf: count=1, height=NodeHeight
  Result^.TotalCount := 1;
  Result^.TotalHeight := GetDefaultNodeHeight;
end;

procedure TTyTreeView.FreeNodeMem(Node: PTyTreeNode);
begin
  FreeMem(Node);
end;

procedure TTyTreeView.SetNodeDataSize(AValue: Integer);
begin
  if FNodeDataSize = AValue then Exit;
  { 条目模式征用了数据块的头 4 字节,所以 app 的数据块与 Items 互斥 —— 同一段
    内存两个主人,静默让一边赢就是数据损坏。 }
  if (AValue > 0) and (FItems <> nil) and (FItems.Count > 0) then
    ItemModeConflict('NodeDataSize');
  // Must be set before any nodes exist (changes the allocation stride).
  FNodeDataSize := AValue;
  UpdateNodeAllocSize;
end;

{ 分配步长的唯一出口。条目模式下块首 4 字节是控件自己的条目下标槽;虚拟模式下
  这一段不存在,步长与条目模型进来之前逐字节相同。 }
procedure TTyTreeView.UpdateNodeAllocSize;
begin
  if FItemMode then
    FNodeAllocSize := TreeNodeSize + SizeOf(Cardinal)
  else if FNodeDataSize > 0 then
    FNodeAllocSize := TreeNodeSize + FNodeDataSize
  else
    FNodeAllocSize := TreeNodeSize;
end;

function TTyTreeView.GetNodeData(Node: PTyTreeNode): Pointer;
begin
  if (FNodeDataSize <= 0) or (Node = nil) or (Node = FRoot) then
    Result := nil
  else
    Result := PByte(Node) + TreeNodeSize;
end;

{ ===========================================================================
  条目模型 —— 控件侧(设计理由见单元中部 §条目模型)
  =========================================================================== }

{ 冲突闸门。两个数据源同时出现时**报错,不择一**。csLoading 期间只记账:
  .lfm 里 Items 与 OnGetText 谁先流进来是不确定的,在读期间抛会让"报不报错"
  取决于属性顺序,而顺序不是用户写的。 }
procedure TTyTreeView.ItemModeConflict(const AWhat: string);
var
  msg: string;
begin
  msg := Format('TTyTreeView "%s": Items 与 %s 不能同时使用。'
    + 'Items 非空时节点的标题与结构由条目集合拥有;%s 属于虚拟模式。'
    + '二选一:清空 Items 走虚拟模式,或者移除 %s 走条目模式。',
    [Name, AWhat, AWhat, AWhat]);
  if csLoading in ComponentState then
  begin
    if FPendingConflict = '' then FPendingConflict := msg;
    Exit;
  end;
  raise ETyTreeItemMode.Create(msg);
end;

{ 虚拟结构 API 的守卫。物化自己要用 AddChild/SetChildCount,所以留一个后门。 }
procedure TTyTreeView.GuardVirtualStructure(const AWhat: string);
begin
  if FItemMode and not FRebuildingItems then
    ItemModeConflict(AWhat);
end;

procedure TTyTreeView.SetOnGetText(AValue: TTyTreeGetTextEvent);
begin
  if Assigned(AValue) and (FItems <> nil) and (FItems.Count > 0) then
    ItemModeConflict('OnGetText');
  FOnGetText := AValue;
end;

procedure TTyTreeView.SetOnGetTextWithType(AValue: TTyTreeGetTextWithTypeEvent);
begin
  if Assigned(AValue) and (FItems <> nil) and (FItems.Count > 0) then
    ItemModeConflict('OnGetTextWithType');
  FOnGetTextWithType := AValue;
end;

{ 直接赋值(Tree1.Items := Tree2.Items)。TCollection.Assign 清空再按**目标**的
  条目类重建,所以类型不会被源带跑。自赋值必须挡:Assign 会先 Clear,
  然后把空集合还给你。 }
procedure TTyTreeView.SetItems(AValue: TTyTreeNodes);
begin
  if AValue = FItems then Exit;
  FItems.Assign(AValue);
end;

{ 条目下标槽:存 下标+1,于是 AllocMem 的零值天然表示"不是条目建的节点"。 }
procedure TTyTreeView.StampItemRef(ANode: PTyTreeNode; AItemIndex: Integer);
begin
  if (ANode = nil) or (ANode = FRoot) then Exit;
  PCardinal(PByte(ANode) + TreeNodeSize)^ := Cardinal(AItemIndex) + 1;
end;

function TTyTreeView.GetNodeItem(Node: PTyTreeNode): TTyTreeNodeItem;
var
  ref: Cardinal;
begin
  Result := nil;
  if (not FItemMode) or (Node = nil) or (Node = FRoot) or (FItems = nil) then Exit;
  ref := PCardinal(PByte(Node) + TreeNodeSize)^;
  if (ref = 0) or (ref > Cardinal(FItems.Count)) then Exit;
  Result := FItems[Integer(ref) - 1];
end;

{ LCL `Node.Text` 的等价物 —— 两种模式都答"屏幕上那一行真正显示的字"。
  与 GetNodeSearchText 走同一条解析(主列 / ttNormal),于是"显示的"与
  "搜到的"永远是同一个字符串。 }
function TTyTreeView.GetNodeText(Node: PTyTreeNode): string;
begin
  Result := '';
  if (Node = nil) or (Node = FRoot) then Exit;
  Result := GetNodeSearchText(Node);
end;

{ 结构变了:整棵重建。设计期 / 移植来的树是几十到几百个节点,重建是一瞬间的事;
  虚拟模式下这条路根本不会被走到(FItems 为空 → 直接退回虚拟模式)。 }
procedure TTyTreeView.ItemsStructureChanged;
begin
  if csLoading in ComponentState then Exit;   { 到 Loaded 再一次性物化 }
  RebuildFromItems;
end;

{ 属性变了(标题 / 图标 / 展开 / 复选):只回写那一个节点,不动树形。
  否则改一个标题会把整棵树重建掉,选中与展开态全丢 —— 运行时改标题是常事。 }
procedure TTyTreeView.ItemStateChanged(AItem: TTyTreeNodeItem);
begin
  if csLoading in ComponentState then Exit;
  if not FItemMode then Exit;
  ApplyItemToNode(AItem);
  Invalidate;
end;

procedure TTyTreeView.ApplyItemToNode(AItem: TTyTreeNodeItem);
begin
  if (AItem = nil) or (AItem.Node = nil) then Exit;
  AItem.Node^.CheckType  := AItem.CheckType;
  AItem.Node^.CheckState := AItem.CheckState;
  if AItem.Expanded <> (nsExpanded in AItem.Node^.States) then
    ToggleNode(AItem.Node, AItem.Expanded);
end;

{ 物化:把扁平的(Level, Text)序列变成记录树。

  进出模式都在这里,所以"这棵树现在归谁"只有一个决定点:
  Items 空 → 退回虚拟模式(步长复原,树清空);非空 → 条目模式。 }
procedure TTyTreeView.RebuildFromItems;
var
  i, lvl: Integer;
  it: TTyTreeNodeItem;
  node: PTyTreeNode;
  { stack[k] = 当前 Level k 上最后建出来的节点,即 Level k+1 的父亲。 }
  stack: array of PTyTreeNode;
begin
  if FRebuildingItems then Exit;

  if (FItems = nil) or (FItems.Count = 0) then
  begin
    if not FItemMode then Exit;          { 本来就是虚拟模式:一个字节都不动 }
    FItemMode := False;
    UpdateNodeAllocSize;
    Clear;
    Exit;
  end;

  { 自己拥有数据源的后代不能走条目层(见 SupportsItemModel 的说明)。
    这一条要排在其它冲突之前:对这种后代来说,"Items 根本用不了"比
    "Items 和 OnGetText 撞了"更接近真正的原因。 }
  if not SupportsItemModel then
    raise ETyTreeItemMode.CreateFmt('%s "%s" 自己拥有节点数据(它覆写了 DoGetText '
      + '并自行建树),不支持 Items 条目模型。请清空 Items,用它自己的数据源属性。',
      [ClassName, Name]);
  { 进条目模式前先把两边的冲突问清楚 —— 事件是在 Items 之前挂上的那一半。 }
  if Assigned(FOnGetText) then ItemModeConflict('OnGetText');
  if Assigned(FOnGetTextWithType) then ItemModeConflict('OnGetTextWithType');
  if FNodeDataSize > 0 then ItemModeConflict('NodeDataSize');
  if FPendingConflict <> '' then Exit;   { csLoading 期间发现的冲突,留到 Loaded 抛 }

  FRebuildingItems := True;
  try
    FItemMode := True;
    UpdateNodeAllocSize;      { 必须在 Clear 之前:新节点要按新步长分配 }
    Clear;
    SetLength(stack, FItems.Count + 1);
    for i := 0 to FItems.Count - 1 do
    begin
      it := FItems[i];
      lvl := it.Level;
      { 夹紧:.lfm 可以手写出任何一串 Level。首项必须 0,其余至多深 1 层。 }
      if lvl < 0 then lvl := 0;
      if i = 0 then lvl := 0
      else if lvl > FItems[i - 1].Level + 1 then lvl := FItems[i - 1].Level + 1;
      if lvl = 0 then node := AddChild(nil) else node := AddChild(stack[lvl - 1]);
      it.FNode := node;
      it.FLevel := lvl;
      StampItemRef(node, i);
      stack[lvl] := node;
    end;
    { 展开态要在整棵树建好之后再施加:展开一个节点要它的孩子已经在位。 }
    for i := 0 to FItems.Count - 1 do
      ApplyItemToNode(FItems[i]);
  finally
    FRebuildingItems := False;
  end;
  InvalidateTreeLayout;
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
  { 条目模式下树形归 Items。这里放行就等于让两边同时改结构,而条目下标槽
    立刻对不上 —— 静默错行比报错难查得多。物化自己走 FRebuildingItems 后门。 }
  GuardVirtualStructure('SetChildCount / RootNodeCount');
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
  { 自己的名字报自己的错 —— 转手给 SetChildCount 会让消息指向调用者没写的成员。 }
  GuardVirtualStructure('AddChild(PTyTreeNode)（条目模式请用 Items.AddChild）');
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
  anc:        PTyTreeNode;   { ③e E4: ancestor walk to detect the edited subtree }
begin
  { 条目模式:删节点要走 Items.DeleteItem,否则条目还在、节点没了,
    下标槽从此错行。 }
  GuardVirtualStructure('DeleteNode（条目模式请用 Items.DeleteItem）');
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
  { ③f F2: dangling-pointer hygiene for the node drag. If the subtree about to be
    freed contains the drag source or the current drop target (the node itself or
    any descendant), END the drag and null whichever pointer is vanishing — so the
    recursive child-frees + the trailing InvalidateTreeLayout never dereference a
    freed node. (A mid-gesture Clear from an event can hit this; a normal drag
    can't free its own source.) }
  if (FDragNode <> nil) or FDragActive then
  begin
    anc := FDragNode;
    while anc <> nil do
    begin
      if anc = Node then begin EndNodeDrag; Break; end;
      if anc = FRoot then Break;
      anc := anc^.Parent;
    end;
    anc := FDropTarget;
    while anc <> nil do
    begin
      if anc = Node then begin EndNodeDrag; Break; end;
      if anc = FRoot then Break;
      anc := anc^.Parent;
    end;
  end;
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
    ReindexSiblings(nodeParent);

  FreeNodeMem(Node);
  InvalidateTreeLayout;
end;

{ ③c A1 / ③f F1: re-stamp a parent's child list with consecutive 0-based Index
  values (sibling position). Extracted from DeleteNode so MoveNode reuses the SAME
  re-sequence (no parallel renumber math). AParent may be FRoot. }
procedure TTyTreeView.ReindexSiblings(AParent: PTyTreeNode);
var
  child: PTyTreeNode;
  idx:   Cardinal;
begin
  if AParent = nil then Exit;
  child := AParent^.FirstChild;
  idx   := 0;
  while child <> nil do
  begin
    child^.Index := idx;
    Inc(idx);
    child := child^.NextSibling;
  end;
end;

{ ③f F1: True iff APossibleAncestor lies on ANode's Parent chain (ANode itself is
  NOT its own descendant). Walk up to the hidden root / the sentinel above it. }
function TTyTreeView.IsDescendant(ANode, APossibleAncestor: PTyTreeNode): Boolean;
var
  run: PTyTreeNode;
begin
  Result := False;
  if (ANode = nil) or (APossibleAncestor = nil) then Exit;
  run := ANode^.Parent;
  while (run <> nil) and (run <> PTyTreeNode(Self)) do
  begin
    if run = APossibleAncestor then Exit(True);
    if run = FRoot then Break;     // reached the hidden root sentinel; stop
    run := run^.Parent;
  end;
end;

{ ③f F1: the single validity gate for a node move. Shared by MoveNode (which
  re-checks — so a malicious OnDragOver setting Allowed:=True can't bypass it),
  the default OnDragOver, and the drop-mark gating. }
function TTyTreeView.CanMoveNode(ANode, ATarget: PTyTreeNode;
  AMode: TTyTreeDropMode): Boolean;
var
  newParent, afterNode: PTyTreeNode;
begin
  Result := False;
  if (ANode = nil) or (ATarget = nil) then Exit;
  if AMode = dmNone then Exit;
  if ANode = FRoot then Exit;          // the hidden root never moves
  if ANode = ATarget then Exit;
  { circular-reparent guard: can't drop a node into its own subtree. ATarget being
    a descendant of ANode covers ATarget=ANode too, but we checked that already. }
  if IsDescendant(ATarget, ANode) then Exit;

  { no-op guard: compute the would-be (newParent, preceding-sibling) and reject if
    it equals ANode's CURRENT (Parent, PrevSibling) — i.e. the move would leave
    ANode exactly where it is. For dmAbove/dmBelow the new parent is ATarget.Parent;
    for dmOn it is ATarget and the node is appended last (preceding = LastChild). }
  case AMode of
    dmAbove:
      begin
        newParent := ATarget^.Parent;
        afterNode := ATarget^.PrevSibling;       // ANode would sit before ATarget
      end;
    dmBelow:
      begin
        newParent := ATarget^.Parent;
        afterNode := ATarget;                    // ANode would sit after ATarget
      end;
    else { dmOn }
      begin
        newParent := ATarget;
        afterNode := ATarget^.LastChild;         // appended as the last child
      end;
  end;
  { if afterNode = ANode, the slot is the one ANode already occupies relative to
    itself (dmBelow ANode's current prev / dmAbove ANode's current next collapses to
    this); normalise so the comparison below catches it. }
  if afterNode = ANode then afterNode := ANode^.PrevSibling;
  if (newParent = ANode^.Parent) and (afterNode = ANode^.PrevSibling) then Exit;

  Result := True;
end;

{ ③f F1: the pure structural move (see the declaration comment). Reuses
  AdjustTotalCount/AdjustTotalHeight (the ③a spine), ComputeExpandedSubtreeHeight +
  the SetExpanded auto-expand delta, and ReindexSiblings (the ③c re-sequence). }
function TTyTreeView.MoveNode(ANode, ATarget: PTyTreeNode;
  AMode: TTyTreeDropMode): Boolean;
var
  oldParent, newParent, beforeNode: PTyTreeNode;
  subtreeCount: Integer;
  subtreeHeight: Integer;
  childrenH: Integer;
begin
  Result := False;
  if not CanMoveNode(ANode, ATarget, AMode) then Exit;

  oldParent := ANode^.Parent;
  { the height ANode's subtree contributes to a parent that DISPLAYS it is exactly
    ANode^.TotalHeight (== ComputeExpandedSubtreeHeight(ANode)); its node count is
    ANode^.TotalCount. Snapshot both BEFORE relinking. }
  subtreeCount  := Integer(ANode^.TotalCount);
  subtreeHeight := Integer(ANode^.TotalHeight);

  { resolve the destination parent + the existing node ANode will be inserted
    BEFORE (nil = append as last child). }
  case AMode of
    dmAbove:
      begin
        newParent  := ATarget^.Parent;
        beforeNode := ATarget;
      end;
    dmBelow:
      begin
        newParent  := ATarget^.Parent;
        beforeNode := ATarget^.NextSibling;
      end;
    else { dmOn }
      begin
        newParent  := ATarget;
        beforeNode := nil;                 // append last
      end;
  end;

  { ── 1. UNLINK ANode from oldParent's child list ───────────────────────────── }
  if ANode^.PrevSibling <> nil then
    ANode^.PrevSibling^.NextSibling := ANode^.NextSibling
  else
    oldParent^.FirstChild := ANode^.NextSibling;
  if ANode^.NextSibling <> nil then
    ANode^.NextSibling^.PrevSibling := ANode^.PrevSibling
  else
    oldParent^.LastChild := ANode^.PrevSibling;
  Dec(oldParent^.ChildCount);
  ANode^.PrevSibling := nil;
  ANode^.NextSibling := nil;

  { subtract ANode's subtree from the OLD parent chain — only when oldParent
    actually displays its children (expanded, or it is the always-expanded root),
    mirroring DeleteNode. Count is always subtracted (not gated by expansion). }
  AdjustTotalCount(oldParent, -subtreeCount);
  if (nsExpanded in oldParent^.States) or (oldParent = FRoot) then
    AdjustTotalHeight(oldParent, -subtreeHeight);
  if oldParent^.ChildCount = 0 then
    Exclude(oldParent^.States, nsHasChildren);

  { ── 1b. MATERIALISE a lazy dmOn target's children BEFORE linking ANode ──────
    A VirtualTree target may carry nsHasChildren with ChildCount=0 (its real
    children not yet built). Linking ANode first would bump ChildCount to 1, and
    InitChildren's `ChildCount>0` guard would then early-exit and DISCARD those
    pending children. So build them now (while ChildCount is still 0): ANode then
    appends AFTER the real children. InitChildren legitimately grows TotalCount by
    the materialised children (exactly as a user expanding the node would) — that
    is correct, not a conservation violation; the dmOn auto-expand height delta
    below recomputes over the now-existing children. (newParent <> oldParent here:
    a lazy ChildCount=0 target can't already be ANode's parent.) }
  if (AMode = dmOn) and (newParent <> FRoot) and
     (nsHasChildren in newParent^.States) and (newParent^.ChildCount = 0) then
    InitChildren(newParent);

  { ── 2. LINK ANode into newParent before beforeNode (nil = append last) ─────── }
  ANode^.Parent := newParent;
  if beforeNode = nil then
  begin
    // append as last child
    ANode^.PrevSibling := newParent^.LastChild;
    if newParent^.LastChild <> nil then
      newParent^.LastChild^.NextSibling := ANode
    else
      newParent^.FirstChild := ANode;
    newParent^.LastChild := ANode;
  end
  else
  begin
    // insert before beforeNode
    ANode^.NextSibling := beforeNode;
    ANode^.PrevSibling := beforeNode^.PrevSibling;
    if beforeNode^.PrevSibling <> nil then
      beforeNode^.PrevSibling^.NextSibling := ANode
    else
      newParent^.FirstChild := ANode;
    beforeNode^.PrevSibling := ANode;
  end;
  Inc(newParent^.ChildCount);

  { count always propagates up the NEW chain (conserves the root total). }
  AdjustTotalCount(newParent, subtreeCount);

  { newParent now has a child. Mark it (unless it is the hidden root, which never
    carries nsHasChildren — same rule as AddChild). }
  if (newParent <> FRoot) and not (nsHasChildren in newParent^.States) then
    Include(newParent^.States, nsHasChildren);

  { height onto the NEW chain: }
  if (AMode = dmOn) and (newParent <> FRoot)
     and not (nsExpanded in newParent^.States) then
  begin
    { auto-expand the (previously collapsed / leaf) target so the drop is visible.
      Mirror SetExpanded's expand path EXACTLY: ANode is already linked, so
      ComputeExpandedSubtreeHeight(newParent) now includes it; the delta over
      newParent's current (collapsed) TotalHeight is the whole now-visible child
      block (ANode's subtree + any pre-existing children). }
    Include(newParent^.States, nsExpanded);
    childrenH := ComputeExpandedSubtreeHeight(newParent) - Integer(newParent^.TotalHeight);
    if childrenH <> 0 then AdjustTotalHeight(newParent, childrenH);
  end
  else if (nsExpanded in newParent^.States) or (newParent = FRoot) then
    { newParent already displays its children → add just ANode's subtree height. }
    AdjustTotalHeight(newParent, subtreeHeight);
  { (newParent collapsed and NOT dmOn — i.e. dmAbove/dmBelow under a collapsed
    parent — adds nothing: ANode stays hidden, consistent with AddChild.) }

  { ── 3. re-stamp Index on BOTH sibling lists (③c re-sequence). When oldParent =
    newParent the second call simply re-confirms the first; cheap + correct.
    Cost: O(siblings) per affected parent (Index is the node's positional rank —
    same class as DeleteNode's reindex). Fine for typical trees; pathological only
    for a huge flat sibling list (thousands+ direct children). ──────────────────── }
  ReindexSiblings(oldParent);
  if newParent <> oldParent then
    ReindexSiblings(newParent);

  InvalidateTreeLayout;
  Result := True;
end;

{ ③f F2: end any in-progress node drag — clear all drag state + repaint (drops the
  drop-mark). Idempotent; safe from MouseUp / Esc / teardown / option-off. }
procedure TTyTreeView.EndNodeDrag;
begin
  FDragActive := False;
  FDragNode   := nil;
  FDropTarget := nil;
  FDropMode   := dmNone;
  { ③f F2 review: reset the drag cursor here. The only Cursor:=crDefault in
    MouseMove is gated behind (Columns.Count>0) and hoColumnResize, so a 0-column
    tree (the VirtualTree case) would otherwise keep crDrag/crNoDrop forever after
    a drag. Also drop the node-drag mouse capture (FIX 5) if we took it. }
  OverrideCursor(False, crDefault);
  if HandleAllocated and MouseCapture then MouseCapture := False;
  Invalidate;
end;

{ ③f F3: seed the active-drag state directly (test/descendant seam — see the
  protected declaration). Flips FDragActive True so the drop-mark in RenderTo
  paints; no Invalidate (the caller renders explicitly). }
procedure TTyTreeView.SetActiveDragState(ASource, ATarget: PTyTreeNode;
  AMode: TTyTreeDropMode);
begin
  FDragActive := True;
  FDragNode   := ASource;
  FDropTarget := ATarget;
  FDropMode   := AMode;
end;

{ ③f F2: split the cursor's device-px Y across ATarget's visible row band into a
  drop mode. Uses GetCellRect (the SAME row-rect math RenderTo paints into) so the
  thirds line up with the painted row; dmNone when ATarget is nil or off-screen. }
function TTyTreeView.DropModeFromY(Target: PTyTreeNode; AY: Integer): TTyTreeDropMode;
var
  r: TRect;
  rTop, h, third: Integer;
begin
  Result := dmNone;
  if Target = nil then Exit;
  { the main column gives the whole row band; Column = Header.MainColumn (or the
    0-column whole-row rect). }
  if not GetCellRect(Target, FHeader.MainColumn, r) then Exit;
  rTop := r.Top;
  h    := r.Bottom - r.Top;
  if h <= 0 then Exit;
  third := h div 3;
  if third <= 0 then third := 1;
  if AY < rTop + third then
    Result := dmAbove
  else if AY >= rTop + h - third then
    Result := dmBelow
  else
    Result := dmOn;
end;

procedure TTyTreeView.Clear;
begin
  { 条目模式下 Items 才是树形的真相,所以"清空这棵树"必须连它一起清 ——
    只清记录会留下一集合对不上任何节点的条目。这里不报错而是**照做**:
    Clear 的语义在两种模式下是同一件事("这棵树空了"),不像 AddChild 那样
    在问"谁来决定结构"。清空 Items 会回流到 RebuildFromItems,由它退回虚拟
    模式并走下面真正的清空。物化自己的那次 Clear 走 FRebuildingItems 后门。 }
  if FItemMode and not FRebuildingItems and (FItems <> nil) and (FItems.Count > 0) then
  begin
    FItems.Clear;
    Exit;
  end;
  { ③e E4: any active edit is on a node about to be freed — CANCEL it (no commit)
    BEFORE the teardown so FEditNode can't dangle. (DeleteNode's own subtree check
    would also catch it per-node, but cancelling once up-front is cheaper + clearer
    for a bulk clear.) }
  if FEditing then CancelEdit;
  { ③f F2: a bulk clear frees every node, so any in-progress node drag is on
    vanishing pointers — end it up-front (DeleteNode's per-node check would also
    catch it, but ending once here is cheaper + guarantees FDragNode/FDropTarget
    are nil before the teardown loop). }
  if (FDragNode <> nil) or FDragActive then EndNodeDrag;
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

{ density: default node/row height — stored-sentinel accessors. When not pinned by a
  host/.lfm, follow the --item-height token (18 classic / 38 modern); the classic
  fallback 18 equals the historical default so classic rendering is byte-identical. }
function TTyTreeView.GetDefaultNodeHeight: Integer;
begin
  if FDefaultNodeHeightExplicit then
    Result := FDefaultNodeHeight
  else
    Result := TyDensityMetric(ActiveController, 18, '--item-height');
end;

procedure TTyTreeView.SetDefaultNodeHeight(AValue: Integer);
begin
  if AValue < 1 then AValue := 1;
  FDefaultNodeHeightExplicit := True;   { even if the value equals the fallback, the host meant to pin it }
  if FDefaultNodeHeight = AValue then Exit;
  FDefaultNodeHeight := AValue;
  Invalidate;
end;

{ ③d B1: per-node row-height accessors. }
function TTyTreeView.GetNodeHeight(Node: PTyTreeNode): Integer;
begin
  if Node = nil then Result := GetDefaultNodeHeight
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
  DoInitNode(Node^.Parent, Node, initStates);
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
    DoExpanding(Node, allowed);
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
function TTyTreeView.GetNodeAtOffset(Y: Integer; out ANodeTop: Integer): PTyTreeNode;
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
    • multi-column  → TyColumnSpan(col, CR.Left + FOffsetX, APPI)
      -- the shared column-x source, which RenderTo's paint loop, the header strip
      and the drag overlay all call too, so there is nothing left to keep in step.
  The vertical extent is always [ARowTop .. ARowTop + ARowH].

  Returns False only when a REAL column index does not resolve to a visible
  column (out of range / coVisible off); the main/0-column cases always succeed. }
function TTyTreeView.NodeCaptionSlots(Node: PTyTreeNode; ACellLeft, ACellRight, APPI: Integer;
  AIsMainColumn: Boolean): TTyTreeCaptionSlots;
var
  level: Integer;
begin
  if Node <> nil then level := GetNodeLevel(Node) else level := 0;
  Result := TyTreeCaptionSlots(ACellLeft, ACellRight, APPI, FIndent, level,
    FShowRoot,
    { A checkbox slot is reserved only when the tree supports check marks AND this
      node actually asked for one -- the paint, the hit test and the editor all
      have to ask that same pair of questions or the caption shifts by Scale(16). }
    (toCheckSupport in FOptions) and (Node <> nil) and (Node^.CheckType <> ctNone),
    { The image slot is reserved whenever a list is assigned, even if THIS node
      resolves no icon: a row whose caption slid left when its icon was missing
      would read as a layout fault, so the slot is held open. }
    (FImages <> nil) and (FImages.Count > 0),
    AIsMainColumn,
    { The direction is asked here and NOT passed in by the caller, so the six consumers
      cannot disagree about which way this tree reads. }
    RtlLayout);
end;

procedure TTyTreeView.MainCellAnchor(const CR: TRect; APPI: Integer;
  out ALeft, ARight: Integer);
{ 主列单元格的两条边,换算到 GetNodeAtPoint 的内容坐标系(x=0 即 contentLeft)。
  绘制侧的单元格来自 InternalCellRect,其 Left = (CR.Left + FOffsetX) + Scale(col.Left);
  这里减掉同一个 contentLeft,得到的就是同一组整数 —— 同一个 MulDiv、同一次反射,
  不会有第二次取整。走 InternalCellRect 而不是自己取列,是为了不让"哪一列是主列"
  (越界判断、coVisible、NoColumn→MainColumn)这套策略出现第二份。

  两条边一起给:槽位走查镜像时要知道自己被反射在哪个格子里,只给左边就得让调用方
  自己再算一次宽度,那就又是一份重复。 }
var
  cell: TRect;
begin
  ALeft  := 0;
  { 0-column tree: the single cell IS the main column and the paint anchors it at
    contentLeft, which is content x 0. Guarded here rather than left to
    InternalCellRect, whose 0-column branch answers CR.Left (not contentLeft) —
    the two differ by FOffsetX once such a tree scrolls horizontally. }
  ARight := (CR.Right - CR.Left) - FOffsetX;
  if (FHeader = nil) or (FHeader.Columns.Count = 0) then Exit;
  { False when MainColumn is out of range or hidden — exactly the case in which the
    paint's `colIdx = MainColumn` branch never fires and no chrome is drawn at all. }
  if not InternalCellRect(CR, 0, 0, NoColumn, APPI, cell) then Exit;
  ALeft  := cell.Left  - (CR.Left + FOffsetX);
  ARight := cell.Right - (CR.Left + FOffsetX);
end;

function TTyTreeView.InternalCellRect(const CR: TRect;
  ARowTop, ARowH, AColumn, APPI: Integer; out ACellRect: TRect): Boolean;
var
  col: TTyColumn;
  colObj: TObject;
  effCol: Integer;
  span: TTyColumnSpan;
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
  if not (colObj is TTyColumn) then Exit;
  col := TTyColumn(colObj);
  if not (coVisible in col.Options) then Exit;

  { The ONE column-x source (tyControls.Columns.TyColumnSpan), asked through the ONE
    description of this control's axis -- origin, density and reading direction together,
    so a mirrored tree cannot have a paint on one axis and a hit test on another. }
  span := col.Span(ColumnAxis(CR, APPI));
  ACellRect := Rect(span.Left, ARowTop, span.Right, ARowTop + ARowH);
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
  seed := GetNodeAtOffset(firstNodeY, firstTop);
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
  level: Integer;
  { Per-row chrome geometry, from the ONE shared walk (NodeCaptionSlots). The
    indent/button/checkbox/image widths that used to be four separate locals
    accumulated by hand now all live here. }
  slots: TTyTreeCaptionSlots;
  nodeStates: TTyStateSet;
  txt: string;
  ghosted: Boolean;
  imgIdx: Integer;
  selIdx, ovlIdx: Integer;      { ikSelected / ikOverlay answers for the current row }
  rangeXNew: Integer;
  inset, insetLogical: Integer;
  savedClip: TRect;
  anc: PTyTreeNode;
  ancLevel, ancMidX, ancMidY, ancSlotX: Integer;
  measW: Integer;
  contentLeft: Integer;
  gSz, slotBaseX: Integer;
  { ── C (columns) variables ───────────────────────────────────────────────── }
  colSpan: TTyColumnSpan;       // shared column-x source result (see TyColumnSpan)
  useColumns: Boolean;          // True when Columns.Count > 0
  hasHeader: Boolean;           // True when hoVisible and useColumns
  headerH: Integer;             // device-px header band height
  headerBandRect: TRect;        // device rect for the header band
  headerBgStyle, headerSecStyle: TTyStyleSet;
  colCount, posIdx, colIdx: Integer;
  col: TTyColumn;
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
  { B2: checkbox APPEARANCE only -- the slot's x and width come from `slots`. }
  cbStyle: TTyStyleSet;        // resolved TyTreeCheckBox style
  cbBoxRect: TRect;            // device rect of the box/circle within the slot
  cbBoxSize: Integer;          // device-px side of the drawn box/circle
  { Node images are drawn via GDI onto ACanvas AFTER EndPaint (see below), so
    collect their device-coord positions during the row loop instead of drawing
    them into the BGRA layer. Drawing an ImageList into TTyPainter.Bitmap.Canvas
    worked on Windows (the LCL RawImage→bitmap conversion aliases the BGRA data
    buffer there) but was silently dropped on Qt/GTK, where the bitmap is a
    separate buffer the EndPaint rebuild-from-data discards. }
  { Ghost travels with the icon: the OnGetImageIndex handler answers per NODE, and the
    icons are drawn later in one post-EndPaint GDI pass, so the flag has to be carried
    rather than re-asked. It used to be collected into a local and dropped, which is why
    a `var Ghosted := True` from an app had no effect anywhere. }
  pendingIcons: array of record X, Y, Idx: Integer; Ghost: Boolean; end;
  pendingCount: Integer;
  iIcon: Integer;
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
    { The painter's own direction flag: it resolves every alignment this method passes from
      a reading-order one to a physical one, which is what puts the cell captions and the
      header captions on the correct side. The BOXES are moved by the axis and the slot
      walk below; this lever only moves text inside them. }
    P.BeginPaint(ACanvas, ARect, APPI, RtlLayout);
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
    SBThick := MulDiv(ActiveController.Metric('--scrollbar-size', TyScrollbarSize), APPI, 96);
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

        { Column cell x range (scroll-adjusted, device pixels) -- from the shared
          span source AND the shared axis, so the header cell sits exactly over the body
          cell below it in either reading direction. }
        colSpan   := col.Span(ColumnAxis(CR, APPI));
        cellLeft  := colSpan.Left;
        cellRight := colSpan.Right;

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

        { Column caption rect. The sort glyph's gutter comes off the cell's READING END,
          so mirrored it is taken off the left; leaving it on the right would let the
          caption (which the painter now right-aligns) run under the glyph. }
        colMargin := P.Scale(4);
        if RtlLayout then
          textRect := Rect(clipR.Left + colMargin + sortGlyphSize,
                           headerBandRect.Top,
                           clipR.Right - colMargin,
                           headerBandRect.Bottom)
        else
          textRect := Rect(clipR.Left + colMargin,
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
          { The glyph sits in the gutter the caption rect just gave up -- the cell's
            reading end. Up/down is a direction of ORDER, not of reading, so the arrow
            itself is left alone. }
          if RtlLayout then
            sortBandR := Rect(clipR.Left + colMargin,
                              headerBandRect.Top + P.Scale(2),
                              clipR.Left + colMargin + sortGlyphSize,
                              headerBandRect.Bottom - P.Scale(2))
          else
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

        { The divider on the edge this section shares with its SUCCESSOR -- its right
          reading rightward, its left when mirrored. It has to be the same edge
          DetermineSplitterIndex grabs, or the line a user aims at is not the line that
          resizes; both read it off the span, neither recomputes it. }
        if posIdx < colCount - 1 then
        begin
          if RtlLayout then colCaptionX := cellLeft else colCaptionX := cellRight - 1;
          P.Bitmap.DrawLine(colCaptionX, headerBandRect.Top,
                            colCaptionX, headerBandRect.Bottom,
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
        col := FHeader.Columns.Items[FDragColumn] as TTyColumn;
        colSpan   := col.Span(ColumnAxis(CR, APPI));
        cellLeft  := colSpan.Left;
        cellRight := colSpan.Right;
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
            { Insert caret at the target position's READING START -- the same span edge
              the ghost above and the cells below are drawn from, so the drop mark always
              lands on a real column boundary. Mirrored that is the span's right: a caret
              on the left would mark the gap AFTER the target, i.e. one slot along. }
            colSpan := col.Span(ColumnAxis(CR, APPI));
            if RtlLayout then cellLeft := colSpan.Right - 2 else cellLeft := colSpan.Left;
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
    node := GetNodeAtOffset(firstNodeY, firstTop);
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

    { ── Per-row paint loop ───────────────────────────────────────────────── }
    while (node <> nil) and (rowTop < CR.Bottom) do
    begin
      InitNode(node);   // idempotent; fires OnGetText/nsHasChildren/etc. once

      rowH    := P.Scale(node^.NodeHeight);
      rowRect := Rect(CR.Left, rowTop, CR.Right, rowTop + rowH);

      { ── Row background ─────────────────────────────────────────────────── }
      { LCL parity (comctrls.pp:3656): with HideSelection the highlight is not drawn
        while the control is unfocused, so two side-by-side trees do not both look
        active. It HIDES rather than dims — the row resolves as an ordinary row, so
        no colour is invented in control code; whatever the skin says a plain
        TyTreeNode looks like is what an inactive selection looks like. }
      nodeStates := [];
      if (nsSelected in node^.States) and (Focused or not FHideSelection) then
        nodeStates := [tysSelected]
      else if FHotTrack and (node = FHotNode) then
        nodeStates := [tysHover];

      NodeStyle := ActiveController.Model.ResolveStyle('TyTreeNode', '', nodeStates);

      if tpBackground in NodeStyle.Present then
      begin
        bgRect := rowRect;
        P.FillBackground(bgRect, NodeStyle.Background, 0);
      end;

      { LCL parity (comctrls.pp:3703): a rule under each TOP-LEVEL row. The colour is
        the resolved control border token — the same one the tree-lines use — so a
        skin recolours both together and nothing is hardcoded here. }
      if FShowSeparators and (GetNodeLevel(node) = 0) then
        P.Bitmap.DrawLine(rowRect.Left, rowRect.Bottom - 1,
                          rowRect.Right, rowRect.Bottom - 1,
                          TyColorToBGRA(S.BorderColor), False);

      { Only the node's LEVEL is needed out here (it gates the tree-line block and
        feeds the ancestor guides); every x derived from it comes from the shared
        walk inside each branch, where the cell anchor is known. }
      level := GetNodeLevel(node);

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
            { Every chrome x below is READ from this one walk. The anchor is the
              main column's own cell, so the indent/expander/checkbox/icon land in the
              column being painted; see NodeCaptionSlots. }
            slots := NodeCaptionSlots(node, mainColBase, colCellRight, APPI, True);

            { Tree lines (anchored at mainColBase) }
            if FShowTreeLines and (level > 0) then
            begin
              anc := node^.Parent;
              while (anc <> nil) and (anc <> FRoot) and (anc <> PTyTreeNode(Self)) do
              begin
                ancLevel := GetNodeLevel(anc);
                ancSlotX := TreeLineX(mainColBase, colCellRight,
                              mainColBase + P.Scale((ancLevel + Ord(FShowRoot)) * FIndent)
                                          - (slots.ButtonSlotW shr 1));
                if anc^.NextSibling <> nil then
                  P.Bitmap.DrawLine(ancSlotX, rowTop, ancSlotX, rowTop + rowH,
                    TyColorToBGRA(S.BorderColor), False);
                anc := anc^.Parent;
              end;
              ancMidX := TreeLineX(mainColBase, colCellRight,
                           mainColBase
                             + P.Scale((level - 1 + Ord(FShowRoot)) * FIndent + FIndent)
                             - (slots.ButtonSlotW shr 1));
              ancMidY := rowTop + rowH div 2;
              P.Bitmap.DrawLine(ancMidX, rowTop,    ancMidX, ancMidY,
                TyColorToBGRA(S.BorderColor), False);
              P.Bitmap.DrawLine(ancMidX, ancMidY,
                TreeLineX(mainColBase, colCellRight, mainColBase + slots.IndentPx), ancMidY,
                TyColorToBGRA(S.BorderColor), False);
              if node^.NextSibling <> nil then
                P.Bitmap.DrawLine(ancMidX, ancMidY, ancMidX, rowTop + rowH,
                  TyColorToBGRA(S.BorderColor), False);
            end;

            { Expand button (anchored at mainColBase) }
            if FShowButtons and (nsHasChildren in node^.States) then
            begin
              gSz := slots.ButtonSlotW;
              if rowH < gSz then gSz := rowH;
              slotBaseX := slots.ButtonSlotX + (slots.ButtonSlotW - gSz) div 2;
              btnRect := Rect(
                slotBaseX,
                rowTop + (rowH - gSz) div 2,
                slotBaseX + gSz,
                rowTop + (rowH - gSz) div 2 + gSz
              );
              if btnRect.Right  <= btnRect.Left  then btnRect.Right  := btnRect.Left  + 4;
              if btnRect.Bottom <= btnRect.Top   then btnRect.Bottom := btnRect.Top   + 4;
              { The expander goes through TyDrawGlyph, not TTyPainter.DrawGlyph directly,
                so a theme that overrides --glyph-chevron-down / --glyph-chevron-right
                reaches the tree too. Calling the painter straight bypassed an override
                this library already supports everywhere else. }
              if nsExpanded in node^.States then
                TyDrawGlyph(P, ActiveController, btnRect, tgChevronDown, NodeStyle.TextColor, P.Scale(1), 2)
              else
                TyDrawGlyph(P, ActiveController, btnRect, tgChevronRight, NodeStyle.TextColor, P.Scale(1), 2);
            end;

            { B2: Checkbox slot (main column, after expand button, before image) }
            if (toCheckSupport in FOptions) and (node^.CheckType <> ctNone) then
            begin
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
                slots.CheckX + (slots.CheckW - cbBoxSize) div 2,
                rowTop + (rowH - cbBoxSize) div 2,
                slots.CheckX + (slots.CheckW - cbBoxSize) div 2 + cbBoxSize,
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
            end;

            { Image (main column only) }
            if (FImages <> nil) and (FImages.Count > 0) then
            begin
              imgIdx  := -1;
              ghosted := False;
              DoGetImageIndex(node, ikNormal, colIdx, ghosted, imgIdx);
              { ikSelected / ikOverlay — see ResolveNodeImages' comment in the
                0-column branch; the two paths must ask the same questions. }
              if nsSelected in node^.States then
              begin
                selIdx := imgIdx;
                DoGetImageIndex(node, ikSelected, colIdx, ghosted, selIdx);
                if selIdx >= 0 then imgIdx := selIdx;
              end;
              ovlIdx := -1;
              DoGetImageIndex(node, ikOverlay, colIdx, ghosted, ovlIdx);
              { ③d D1: when this cell is owner-drawn the app owns the image too —
                do NOT collect it into pendingIcons (slot still reserved so the
                row width / chrome layout is unchanged). }
              if (not ownerDrawCell) and (imgIdx >= 0) and (imgIdx < FImages.Count) then
              begin
                { Collect; drawn via GDI onto ACanvas after EndPaint (see below). }
                if pendingCount = Length(pendingIcons) then
                  SetLength(pendingIcons, pendingCount + 32);
                pendingIcons[pendingCount].X   := ARect.Left + slots.ImageX;
                pendingIcons[pendingCount].Y   := ARect.Top  + rowTop + (rowH - FImages.Height) div 2;
                pendingIcons[pendingCount].Idx := imgIdx;
                pendingIcons[pendingCount].Ghost := ghosted;
                Inc(pendingCount);
                if (ovlIdx >= 0) and (ovlIdx < FImages.Count) then
                begin
                  if pendingCount = Length(pendingIcons) then
                    SetLength(pendingIcons, pendingCount + 32);
                  pendingIcons[pendingCount] := pendingIcons[pendingCount - 1];
                  pendingIcons[pendingCount].Idx := ovlIdx;
                  Inc(pendingCount);
                end;
              end;
            end;

            { Caption in main column — skipped for an owner-drawn cell (the app
              fully replaces the cell content via OnDrawNode post-EndPaint). }
            if not ownerDrawCell then
            begin
              colTxt := '';
              if Assigned(FOnGetTextWithType) then
                FOnGetTextWithType(Self, node, colIdx, ttNormal, colTxt)
              else
                DoGetText(node, colTxt);

              { Both edges from the walk: mirrored, the caption's far end is where the
                icon slot begins, and using the cell's own right edge would run the text
                straight under the chrome. }
              textRect := Rect(slots.CaptionX + slots.TextPad, rowTop,
                               slots.CaptionRight - slots.TextPad, rowTop + rowH);
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
              { The non-main branch of the SAME walk: no chrome, just the flat pad.
                Sourced here too so CellTextRect (which the inline editor sits on)
                and this paint cannot disagree about what that pad is. }
              slots := NodeCaptionSlots(node, colCellLeft, colCellRight, APPI, False);
              colMargin := slots.TextPad;
              colCaptionX := slots.CaptionX + slots.TextPad;

              colTxt := '';
              if Assigned(FOnGetTextWithType) then
                FOnGetTextWithType(Self, node, colIdx, ttNormal, colTxt)
              else
                DoGetText(node, colTxt);   // fallback for compat

              colAlign := col.Alignment;
              textRect := Rect(colCaptionX, rowTop,
                               slots.CaptionRight - colMargin, rowTop + rowH);
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

        { The 0-column tree's single cell IS the main column, so the same walk runs
          with the content origin as its anchor. Its far edge is the VISIBLE frame
          (CR.Right), which is what the caption has always been clipped to and therefore
          what the mirrored walk must reflect in. }
        slots := NodeCaptionSlots(node, contentLeft, CR.Right, APPI, True);

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
            ancSlotX := TreeLineX(contentLeft, CR.Right,
                          contentLeft + P.Scale((ancLevel + Ord(FShowRoot)) * FIndent)
                                      - (slots.ButtonSlotW shr 1));
            if anc^.NextSibling <> nil then
              P.Bitmap.DrawLine(ancSlotX, rowTop, ancSlotX, rowTop + rowH,
                TyColorToBGRA(S.BorderColor), False);
            anc := anc^.Parent;
          end;

          { Elbow at this node's level: vertical half + horizontal stub. }
          ancMidX := TreeLineX(contentLeft, CR.Right,
                       contentLeft
                         + P.Scale((level - 1 + Ord(FShowRoot)) * FIndent + FIndent)
                         - (slots.ButtonSlotW shr 1));
          ancMidY := rowTop + rowH div 2;
          P.Bitmap.DrawLine(ancMidX, rowTop,    ancMidX, ancMidY,
            TyColorToBGRA(S.BorderColor), False);
          P.Bitmap.DrawLine(ancMidX, ancMidY,
            TreeLineX(contentLeft, CR.Right, contentLeft + slots.IndentPx), ancMidY,
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
          gSz := slots.ButtonSlotW;
          if rowH < gSz then gSz := rowH;
          slotBaseX := slots.ButtonSlotX + (slots.ButtonSlotW - gSz) div 2;
          btnRect := Rect(
            slotBaseX,
            rowTop + (rowH - gSz) div 2,
            slotBaseX + gSz,
            rowTop + (rowH - gSz) div 2 + gSz
          );
          if btnRect.Right  <= btnRect.Left  then btnRect.Right  := btnRect.Left  + 4;
          if btnRect.Bottom <= btnRect.Top   then btnRect.Bottom := btnRect.Top   + 4;
          { The expander goes through TyDrawGlyph, not TTyPainter.DrawGlyph directly, so
            a theme that overrides --glyph-chevron-down / --glyph-chevron-right reaches
            the tree too. Calling the painter straight bypassed an override this library
            already supports everywhere else. }
          if nsExpanded in node^.States then
            TyDrawGlyph(P, ActiveController, btnRect, tgChevronDown, NodeStyle.TextColor, P.Scale(1), 2)
          else
            TyDrawGlyph(P, ActiveController, btnRect, tgChevronRight, NodeStyle.TextColor, P.Scale(1), 2);
        end;

        { ── B2: Checkbox slot (after expand button, before image) ──────── }
        if (toCheckSupport in FOptions) and (node^.CheckType <> ctNone) then
        begin
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
            slots.CheckX + (slots.CheckW - cbBoxSize) div 2,
            rowTop + (rowH - cbBoxSize) div 2,
            slots.CheckX + (slots.CheckW - cbBoxSize) div 2 + cbBoxSize,
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
        end;

        { ── Image ────────────────────────────────────────────────────────── }
        { The image slot is RESERVED whenever an image list is assigned (matching
          GetNodeAtPoint's hpImage zone); slots.ImageW carries that reservation,
          including into the FRangeX width below. }
        if (FImages <> nil) and (FImages.Count > 0) then
        begin
          imgIdx  := -1;
          ghosted := False;
          DoGetImageIndex(node, ikNormal, -1, ghosted, imgIdx);
          { TTyVTImageKind advertises four kinds and only ikNormal was ever asked for,
            so a folder tree could not show an open-folder icon on the selected row and
            an overlay badge was unreachable.
            ikSelected: asked only for a selected row, SEEDED with the normal index —
            a handler that ignores the kind leaves it alone, so a tree written before
            this change renders identically.
            ikOverlay: seeded -1 and drawn on top of the normal icon at the same
            position when the handler answers, which is what a badge is.
            ikState still has no answer here: it needs a SECOND image list
            (LCL's StateImages) and its own slot in the row layout. }
          if nsSelected in node^.States then
          begin
            selIdx := imgIdx;
            DoGetImageIndex(node, ikSelected, -1, ghosted, selIdx);
            if selIdx >= 0 then imgIdx := selIdx;
          end;
          ovlIdx := -1;
          DoGetImageIndex(node, ikOverlay, -1, ghosted, ovlIdx);
          { ③d D1: owner-drawn cell owns its image — do not collect it. }
          if (not ownerDrawCell) and (imgIdx >= 0) and (imgIdx < FImages.Count) then
          begin
            { Collect; drawn via GDI onto ACanvas after EndPaint (see below). }
            if pendingCount = Length(pendingIcons) then
              SetLength(pendingIcons, pendingCount + 32);
            pendingIcons[pendingCount].X   := ARect.Left + slots.ImageX;
            pendingIcons[pendingCount].Y   := ARect.Top  + rowTop + (rowH - FImages.Height) div 2;
            pendingIcons[pendingCount].Idx := imgIdx;
            { The Ghost carry landed on the multi-column branch only, so in the DEFAULT
              0-column tree `var Ghosted := True` still reached nothing. Same fix, this
              side of the branch. }
            pendingIcons[pendingCount].Ghost := ghosted;
            Inc(pendingCount);
            if (ovlIdx >= 0) and (ovlIdx < FImages.Count) then
            begin
              if pendingCount = Length(pendingIcons) then
                SetLength(pendingIcons, pendingCount + 32);
              pendingIcons[pendingCount] := pendingIcons[pendingCount - 1];
              pendingIcons[pendingCount].Idx := ovlIdx;
              Inc(pendingCount);
            end;
          end;
        end;

        { ── Caption ─────────────────────────────────────────────────────── }
        { ③d D1: skipped for an owner-drawn cell (app fully replaces it). }
        txt := '';
        if not ownerDrawCell then
          DoGetText(node, txt);

        if not ownerDrawCell then
        begin
          textRect := Rect(slots.CaptionX + slots.TextPad, rowTop,
                           slots.CaptionRight, rowTop + rowH);
          if (textRect.Left < textRect.Right) and (txt <> '') then
            P.DrawText(textRect, txt,
              NodeStyle.FontName, ResolveFontSize(NodeStyle), NodeStyle.FontWeight,
              NodeStyle.TextColor, taLeftJustify, tlCenter, True);

          if Assigned(FOnPaintText) then
            FOnPaintText(Self, ACanvas, node, -1, ttNormal);
        end;

        { ── FRangeX accumulation ─────────────────────────────────────────── }
        { Pure content WIDTH for this row — independent of CR.Left, FOffsetX and now of
          the reading direction, so the H-scroll range never drifts with either. It is the
          chrome the shared walk reserved, read back off the record's own widths rather
          than restated: restating that sum is what used to let the scroll range disagree
          with the paint. Taking it as (CaptionX - anchor) was the same quantity only
          while the walk ran left-to-right; mirrored, CaptionX is the caption's own left
          and that subtraction answers ~0. }
        if txt <> '' then
        begin
          measW := slots.IndentPx + slots.CheckW + slots.ImageW + slots.TextPad +
            P.MeasureText(txt, NodeStyle.FontName, ResolveFontSize(NodeStyle),
                          NodeStyle.FontWeight).cx + P.Scale(4);
          if measW > rangeXNew then
            rangeXNew := measW;
        end;
      end; { end ③a single-column path }

      node   := GetNextVisibleNoInit(node);
      Inc(rowTop, rowH);
    end;

    { ── ③f F3 ── drop-mark overlay (drawn INTO the BGRA layer, before EndPaint) ─
      A node drag in progress paints a mark on the prospective drop target so the
      user sees where the node will land. Drawn here (after the rows, while the
      content ClipRect is still active) into P.Bitmap — the SAME layer the rows
      use, so the alpha-blit in EndPaint preserves it (a GDI draw to ACanvas would
      be erased; cf. d427095). Accent comes from the THEME — the TyTreeNode:selected
      background is --accent — exactly the source the ③b header drag-mark uses; no
      hard-coded color, no new typeKey. Fully gated: a tree that is not dragging
      (FDragActive False), has no mode (dmNone) or no/off-screen target never enters
      here, so Options=[] / non-drag renders are byte-identical. }
    if FDragActive and (FDropMode <> dmNone) and (FDropTarget <> nil) then
    begin
      mainColBase := NoColumn;
      if useColumns then mainColBase := FHeader.MainColumn;
      if GetCellRect(FDropTarget, mainColBase, rowRect) then
      begin
        { Theme accent (same resolution as the header drag overlay above). }
        NodeStyle := ActiveController.Model.ResolveStyle('TyTreeNode', '', [tysSelected]);
        if tpBackground in NodeStyle.Present then
          accentPx := TyColorToBGRA(NodeStyle.Background.Color)
        else
          accentPx := TyColorToBGRA(S.BorderColor);
        { Text-left of the target's main cell → the line starts at the caption
          indent so it reads as "between these siblings at this level". }
        textRect := CellTextRect(FDropTarget, mainColBase, rowRect);
        case FDropMode of
          { dmAbove / dmBelow: a Scale(2)-thick accent line at the target row's
            top / bottom, from the caption indent to the content right edge. }
          dmAbove:
            P.Bitmap.FillRect(textRect.Left, rowRect.Top,
                              CR.Right,      rowRect.Top + P.Scale(2), accentPx);
          dmBelow:
            P.Bitmap.FillRect(textRect.Left, rowRect.Bottom - P.Scale(2),
                              CR.Right,      rowRect.Bottom,           accentPx);
          { dmOn: an accent outline around the whole target row (distinct shape
            from the line, so "make child" reads differently from "reorder"). The
            HORIZONTAL extent spans the full content width (CR.Left..CR.Right, like
            the row fill) — not just the main column's cell — so in multi-column
            mode the outline frames the whole row, not one column. Vertical bounds
            come from the target's row band (rowRect.Top/Bottom). }
          dmOn:
            begin
              inset := P.Scale(2);   // outline thickness (reuse inset scratch)
              P.Bitmap.FillRect(CR.Left, rowRect.Top,
                                CR.Right, rowRect.Top + inset, accentPx);               // top
              P.Bitmap.FillRect(CR.Left, rowRect.Bottom - inset,
                                CR.Right, rowRect.Bottom, accentPx);                    // bottom
              P.Bitmap.FillRect(CR.Left, rowRect.Top,
                                CR.Left + inset, rowRect.Bottom, accentPx);             // left
              P.Bitmap.FillRect(CR.Right - inset, rowRect.Top,
                                CR.Right, rowRect.Bottom, accentPx);                    // right
            end;
        end;
      end;
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
      3) OnAfterCellPaint (overlays, on top of everything).

      The per-cell bracket is Canvas.SaveHandleState/RestoreHandleState and NOT
      the raw SaveDC/RestoreDC it used to be. RestoreDC swaps the DC's selected
      font/pen/brush back, but an LCL TCanvas caches which of ITS objects it
      believes are selected and only re-selects one when a property actually
      CHANGES -- so after the first callback the cache is a lie, and a handler
      that assigns the same Font.Color (or Pen.Color) it assigned last cell gets
      a silent no-op and draws with whatever the restore put back. That is not a
      defect a host can see or defend against: the tree's own Owner-draw example
      lost every child caption to it (white ink on a white row), while the rows
      whose handler happened to flip Font.Bold escaped, because the flip forced
      the re-select. The canvas-aware pair calls DeselectHandles on both sides,
      so the cache never outlives the DC state it describes -- the same bracket
      LCL's own per-cell owner-draw hook uses (TCustomGrid.DoDrawCell around
      OnDrawCell, grids.pas), and what LCLIntf's own header tells LCL users to
      reach for instead of SaveDC/RestoreDC. Note FillRect is NOT affected (LCL
      hands it the brush handle explicitly), which is why the fill-based tests
      here stayed green through all of it. }

    { 1) OnDrawNode — full cell-content replacement (toOwnerDraw + handler). }
    if pendingDrawCount > 0 then
      for iCb := 0 to pendingDrawCount - 1 do
      begin
        ACanvas.SaveHandleState;
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
          ACanvas.RestoreHandleState;
        end;
      end;

    { 2) Node images: draw via GDI onto the (now composited) control canvas.
      Drawing into the BGRA layer's Canvas was erased by the EndPaint rebuild on
      Qt/GTK. The X/Y were captured in ARect-relative device coords (== ACanvas
      device coords here); CR is painter-local (0-based), so the clip is offset
      by ARect. Owner-drawn cells were already skipped at collection time. }
    if (pendingCount > 0) and (FImages <> nil) then
    begin
      ACanvas.SaveHandleState;
      try
        IntersectClipRect(ACanvas.Handle,
          ARect.Left + CR.Left,  ARect.Top + CR.Top,
          ARect.Left + CR.Right, ARect.Top + CR.Bottom);
        for iIcon := 0 to pendingCount - 1 do
          { NOTE the fifth argument. FImages here is LCL's TCustomImageList, whose Draw is
            Draw(Canvas, X, Y, Index, Enabled) -- Enabled, not Ghosted, and it happens to
            accept a Boolean in that position either way, so passing the flag straight
            through compiled cleanly and drew EVERY icon disabled. Ghosted is the negation
            of Enabled, and the greyed rendering LCL does for a disabled icon is exactly
            the "unavailable" look Ghosted asks for. }
          FImages.Draw(ACanvas, pendingIcons[iIcon].X, pendingIcons[iIcon].Y,
            pendingIcons[iIcon].Idx, not pendingIcons[iIcon].Ghost);
      finally
        ACanvas.RestoreHandleState;
      end;
    end;

    { 3) OnAfterCellPaint — overlay on top of default content + OnDrawNode. }
    if pendingAfterCount > 0 then
      for iCb := 0 to pendingAfterCount - 1 do
      begin
        ACanvas.SaveHandleState;
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
          ACanvas.RestoreHandleState;
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

  The x-zones come from NodeCaptionSlots — the same walk RenderTo paints with — so
  the slot WIDTHS and CONDITIONS cannot drift from the chrome on screen, and the
  ANCHOR is now MainCellAnchor, so neither can the cell they sit in.

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
  slots: TTyTreeCaptionSlots;
  mainX, mainR: Integer;
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

  node := GetNodeAtOffset(absY, nodeTop);
  if node = nil then Exit;

  { Make sure the node is initialised so nsHasChildren is reliable }
  InitNode(node);

  { The same slot walk RenderTo paints with — read, not re-derived — anchored on the
    cell the main column actually occupies. The anchor used to be a bare 0, i.e.
    "the main column starts at the left edge of the content": true in the 0-column
    tree and whenever MainColumn is the leftmost visible column, false otherwise,
    and then every zone below sat Scale(MainColumn.Left) px left of the chrome on
    screen — the expander a user clicked answered hpLabel and the node would not
    expand. MainCellAnchor is 0 in exactly the cases where the old constant was right. }
  MainCellAnchor(CR, PPI, mainX, mainR);
  slots := NodeCaptionSlots(node, mainX, mainR, PPI, True);

  { The ladder below is the ONE consumer of this record that reads an ORDER rather than a
    rectangle, which is why the record carries a direction bit at all (see its comment).
    Every chrome test is now a half-open CONTAINMENT of a [X, X+W) slot, and those are
    direction-free -- a reflected slot is still a slot. Only the OPEN-ENDED zones need
    the bit: "outside the main cell", "off the content's leading edge" and "the indent
    before the expander" sit on opposite sides in the two directions, and they are the
    only three things here that are not a box. Testing the boxes FIRST is what shrinks
    the directional part to those three. }
  if (not slots.RightToLeft) and (absX < 0) then
  begin
    { Off the content's leading edge entirely (scrolled past x 0). }
    APart := hpIndent;
    Result := node;
  end
  else if (not slots.RightToLeft) and (absX < mainX) then
  begin
    { Outside the main column's cell, on the side that carries no chrome: a NON-main
      cell's body — the paint draws none there. }
    APart  := hpLabel;
    Result := node;
  end
  else if slots.RightToLeft and (absX >= mainR) then
  begin
    { The mirror of the same thing: past the main cell's trailing edge. It has to be
      tested BEFORE the indent zone below, exactly as its left-to-right twin is, because
      the indent runs right up to the cell edge and would otherwise swallow the whole of
      the next column. }
    APart  := hpLabel;
    Result := node;
  end
  else if (slots.CheckW > 0) and
          (absX >= slots.CheckX) and (absX < slots.CheckX + slots.CheckW) then
  begin
    { A slot with zero width is one this node does not have, so this falls through
      exactly when the painter drew nothing. }
    APart  := hpCheckBox;
    Result := node;
    { Column detection happens below — don't Exit here }
  end
  else if (slots.ImageW > 0) and
          (absX >= slots.ImageX) and (absX < slots.ImageX + slots.ImageW) then
  begin
    APart  := hpImage;
    Result := node;
  end
  else if (absX >= slots.ButtonSlotX) and
          (absX < slots.ButtonSlotX + slots.ButtonSlotW) then
  begin
    { In the button slot — classify as hpButton only if the node has children
      AND buttons are shown.  Otherwise treat as hpIndent. }
    if FShowButtons and (nsHasChildren in node^.States) then
      APart := hpButton
    else
      APart := hpIndent;
    Result := node;
  end
  else if (not slots.RightToLeft) and (absX < slots.ButtonSlotX) then
  begin
    { The indent the node earned, before the expander slot at its inner end. }
    APart  := hpIndent;
    Result := node;
  end
  else if slots.RightToLeft and (absX >= slots.ButtonSlotX + slots.ButtonSlotW) then
  begin
    { The exact mirror of the branch above it: everything past the expander slot, with no
      upper bound of its own. The bound belongs to the outside-the-cell test earlier in
      the ladder -- writing it here as well would make that test redundant, and a
      redundant branch is one no test can hold in place. }
    APart  := hpIndent;
    Result := node;
  end
  else
  begin
    { Everything past the chrome is the label area, whichever way "past" is. }
    APart  := hpLabel;
    Result := node;
  end;

  { D1: determine which column the X coordinate lands in (when columns exist).
    Device X against the device origin the paint uses (CR.Left + FOffsetX) — the
    identical pair InternalCellRect hands to Span, so the column boundary this
    reports is the boundary that was drawn. It used to convert both down to logical
    px first, which rounded the same edge twice and could hand the last device pixel
    of a column to its right-hand neighbour. }
  if (Result <> nil) and (FHeader <> nil) and (FHeader.Columns.Count > 0) then
    AColumn := FHeader.Columns.ColumnFromPosition(X, ColumnAxis(CR, PPI));
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
  PPI, colIdx: Integer;
  axis: TTyColumnAxis;
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

  { The header strip shares the body's horizontal geometry, so it shares its AXIS --
    origin, density and reading direction together, exactly what the cells are painted
    from. }
  axis := ColumnAxis(CR, PPI);

  { Check for divider (the resizable column's trailing edge within tolerance) — only when
    column resize is enabled; otherwise the divider zone belongs to the clickable
    (sortable) header section so a click near a border still sorts. }
  colIdx := NoColumn;
  if hoColumnResize in FHeader.Options then
    colIdx := FHeader.Columns.DetermineSplitterIndex(X, axis);
  if colIdx <> NoColumn then
  begin
    APart   := hpHeaderDivider;
    AColumn := colIdx;
    Result  := True;
  end
  else
  begin
    { Plain header section hit }
    AColumn := FHeader.Columns.ColumnFromPosition(X, axis);
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
  col: TTyColumn;
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
      col := FHeader.Columns.Items[headerCol] as TTyColumn;
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
      col := FHeader.Columns.Items[headerCol] as TTyColumn;
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
    { Right-click: move focus to the clicked node (mirrors VTV right-down behaviour),
      which avoids a desync where FocusedNode and the visually-highlighted row differ
      when the node was programmatically selected without focus, and keeps keyboard
      nav anchored to the right row.
      LCL parity: this used to be unconditional; it is now RightClickSelect
      (comctrls.pp:3695), so a context menu that must act on the EXISTING selection
      can turn it off. Ours defaults True — the shipped behaviour — where LCL
      defaults False. }
    if FRightClickSelect and (node <> nil) then
      FocusedNode := node;
  end;

  { ③f F2: ARM a node drag (selection above already happened). Gate on toNodeDrag
    + a press on the node's label/image region (NOT the expand button / checkbox —
    each owns its gesture). FDragActive stays False here; MouseMove promotes it
    once the press travels past the threshold. (Left button only — node drag is a
    left-button gesture, like VTV.) }
  if (Button = mbLeft) and (toNodeDrag in FOptions) and
     (FLastMouseHitPart in [hpLabel, hpImage]) and (FLastMouseNode <> nil) then
  begin
    FDragNode     := FLastMouseNode;
    FDragStartPos := Point(X, Y);
    FDragActive   := False;
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

{ Borrow Cursor for the duration of a gesture and give the caller's own cursor back
  when it ends. Mid-gesture swaps (crDrag <-> crNoDrop) go through without disturbing
  the remembered one. Mirrors TTyListView.SetDividerCursor. }
{ 标题的唯一分流点。

  绘制、命中、类型搜索、就地编辑一共五处取标题,写法都是
  `if Assigned(FOnGetTextWithType) then ... else DoGetText(...)`。条目模式下
  OnGetTextWithType 必定为 nil(冲突闸门保证),所以五处**全部**落到这里 ——
  于是"条目模式的标题从哪来"只需要改这一个函数,五处一个字都不用动。
  这同时也是"未使用时逐字节不变"的保证:FItemMode=False 时下面这段不存在。 }
function TTyTreeView.SupportsItemModel: Boolean;
begin
  Result := True;
end;

procedure TTyTreeView.DoGetText(Node: PTyTreeNode; var AText: string);
var
  it: TTyTreeNodeItem;
begin
  if FItemMode then
  begin
    it := GetNodeItem(Node);
    if it <> nil then AText := it.Text;
    Exit;
  end;
  if Assigned(FOnGetText) then FOnGetText(Self, Node, AText);
end;

{ 流式化收尾。.lfm 里的条目是一条一条读进来的,每条都重建一次既慢、又会在
  只读到一半的序列上算 Level(第 3 条的父亲可能还没读到),所以物化推迟到这里。
  读期间攒下的模式冲突也在这里抛:在读期间抛会让"报不报错"取决于 .lfm 里
  Items 与 OnGetText 谁先出现,而那个顺序不是用户写的。 }
procedure TTyTreeView.Loaded;
var
  msg: string;
begin
  inherited Loaded;
  if FPendingConflict <> '' then
  begin
    msg := FPendingConflict;
    FPendingConflict := '';
    raise ETyTreeItemMode.Create(msg);
  end;
  if (FItems <> nil) and (FItems.Count > 0) then
    RebuildFromItems;
end;

procedure TTyTreeView.DoInitNode(AParent, Node: PTyTreeNode;
  var AStates: TTyNodeInitStates);
begin
  if Assigned(FOnInitNode) then FOnInitNode(Self, AParent, Node, AStates);
end;

procedure TTyTreeView.DoExpanding(Node: PTyTreeNode; var AAllowed: Boolean);
begin
  if Assigned(FOnExpanding) then FOnExpanding(Self, Node, AAllowed);
end;

{ 图标与标题同一条约定:条目模式下 ImageIndex / SelectedIndex 由条目拥有。
  和标题不同的是 OnGetImageIndex **不**参与冲突判定 —— 它不是模式的决定者,
  条目没给出图标(-1)时仍然让 app 补一个是合理的组合,不是两个主人。 }
procedure TTyTreeView.DoGetImageIndex(Node: PTyTreeNode; AKind: TTyVTImageKind;
  AColumn: Integer; var AGhosted: Boolean; var AIndex: Integer);
var
  it: TTyTreeNodeItem;
begin
  if FItemMode then
  begin
    it := GetNodeItem(Node);
    if it <> nil then
      case AKind of
        ikNormal:   if it.ImageIndex    >= 0 then AIndex := it.ImageIndex;
        ikSelected: if it.SelectedIndex >= 0 then AIndex := it.SelectedIndex
                    else if it.ImageIndex >= 0 then AIndex := it.ImageIndex;
      end;
  end;
  if Assigned(FOnGetImageIndex) then
    FOnGetImageIndex(Self, Node, AKind, AColumn, AGhosted, AIndex);
end;

procedure TTyTreeView.DoTreeChange(Node: PTyTreeNode);
begin
  if Assigned(FOnChange) then FOnChange(Self, Node);
end;

procedure TTyTreeView.OverrideCursor(AOn: Boolean; AWith: TCursor);
begin
  if AOn then
  begin
    if not FCursorOverridden then
    begin
      FSavedCursor := Cursor;
      FCursorOverridden := True;
    end;
    if Cursor <> AWith then Cursor := AWith;
  end
  else if FCursorOverridden then
  begin
    FCursorOverridden := False;
    Cursor := FSavedCursor;
  end;
end;

procedure TTyTreeView.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  part: TTyTreeHitPart;
  node: PTyTreeNode;
  hPart: TTyTreeHitPart;
  hCol, PPI, newWidth: Integer;
  col: TTyColumn;
  threshold, hitColIdx, targetPos: Integer;
  allowed: Boolean;   { ③f F2: per-move CanMoveNode + OnDragOver verdict }
begin
  hitColIdx := NoColumn;
  targetPos := 0;
  inherited MouseMove(Shift, X, Y);

  { ③f F2: intra-tree node drag. Engaged only when a node was armed on MouseDown
    (FDragNode<>nil) under toNodeDrag — a header column drag arms FDragPending /
    FDragColumn instead, so the two gestures never overlap. }
  if (toNodeDrag in FOptions) and (FDragNode <> nil) then
  begin
    { arm → active once the press travels past Scale(4) manhattan (same threshold
      formula as the column drag-reorder: MulDiv(4, PPI, 96)). }
    if (ssLeft in Shift) and not FDragActive and
       ((Abs(X - FDragStartPos.X) > MulDiv(4, Font.PixelsPerInch, 96)) or
        (Abs(Y - FDragStartPos.Y) > MulDiv(4, Font.PixelsPerInch, 96))) then
    begin
      FDragActive := True;
      { ③f FIX 5: capture the mouse for the duration of the node drag (mirrors the
        header/resize gestures) so a release OUTSIDE the control still reaches
        MouseUp → EndNodeDrag and clears FDragActive. The column drag is mutually
        exclusive (its block Exits before reaching here), so the captures never
        overlap. EndNodeDrag releases it. }
      if HandleAllocated then MouseCapture := True;
    end;

    if FDragActive then
    begin
      { track the drop target + mode under the cursor; let OnDragOver further
        restrict (CanMoveNode is the default + the hard gate). }
      FDropTarget := GetNodeAtPoint(X, Y, part);
      if FDropTarget <> nil then FDropMode := DropModeFromY(FDropTarget, Y)
      else                       FDropMode := dmNone;

      allowed := CanMoveNode(FDragNode, FDropTarget, FDropMode);
      if Assigned(FOnDragOver) then
        FOnDragOver(Self, FDragNode, FDropTarget, FDropMode, allowed);
      { Note (by design): if an OnDragOver handler forces Allowed:=True on a move
        that CanMoveNode rejects, the drop-mark below will paint a "valid" mark,
        but MouseUp's MoveNode re-runs CanMoveNode and HARD-rejects it — CanMoveNode
        is the single hard gate; OnDragOver can only further RESTRICT a valid move,
        not authorise an invalid one. Also: a re-entrant Clear/MoveNode from inside
        OnDragOver is tolerated — the code after this handler does not re-deref the
        drag pointers (it only reads FDropMode and repaints). }
      if not allowed then FDropMode := dmNone;

      if FDropMode <> dmNone then OverrideCursor(True, crDrag)
      else                        OverrideCursor(True, crNoDrop);
      Invalidate;
      Exit;   { skip the normal hover/hot-node update while a drag is active }
    end;
  end;

  { D2: active column resize drag }
  if FResizeColumn <> NoColumn then
  begin
    PPI := Font.PixelsPerInch;
    { The grip is the column's TRAILING edge, and a drag AWAY from the reading start is
      what widens it: rightwards reading rightward, LEFTWARDS when mirrored. This sign is
      not inside any *Rect function, which is why it is the classic silent half-mirror --
      a static screenshot is perfect and the column grows the wrong way the moment anyone
      drags it (§5 item 2). }
    if RtlLayout then
      newWidth := FResizeStartWidth + MulDiv(FResizeStartX - X, 96, PPI)
    else
      newWidth := FResizeStartWidth + MulDiv(X - FResizeStartX, 96, PPI);
    col := FHeader.Columns.Items[FResizeColumn] as TTyColumn;
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
       (coDraggable in (FHeader.Columns.Items[FDragColumn] as TTyColumn).Options) then
    begin
      FDragging := True;
      Invalidate;
    end;

    if FDragging then
    begin
      { Compute the target visual position from the current X — same device origin
        the header strip is painted from, so the column the pointer is over is the
        column under the pointer. }
      PPI       := Font.PixelsPerInch;
      hitColIdx := FHeader.Columns.ColumnFromPosition(X, ColumnAxis(ContentRect, PPI));

      if hitColIdx <> NoColumn then
      begin
        col := FHeader.Columns.Items[hitColIdx] as TTyColumn;
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
    OverrideCursor(GetHeaderHitAt(X, Y, hPart, hCol) and (hPart = hpHeaderDivider),
      crHSplit);
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
  draggedCol: TTyColumn;
  oldPos, newPos: Integer;
begin
  inherited MouseUp(Button, Shift, X, Y);

  { ③f F2: commit an active node drag. MoveNode re-checks CanMoveNode, so an
    OnDragOver that wrongly set Allowed:=True still can't push through an invalid
    move. Fires OnNodeMoved only on a real move. EndNodeDrag clears + repaints.
    Exit so the gesture doesn't fall through to the header paths below. }
  if FDragActive then
  begin
    if (FDropTarget <> nil) and (FDropMode <> dmNone) and
       MoveNode(FDragNode, FDropTarget, FDropMode) then
      if Assigned(FOnNodeMoved) then FOnNodeMoved(Self, FDragNode);
    EndNodeDrag;
    Exit;
  end;
  { a press that armed but never crossed the threshold (FDragNode set, not active)
    leaves no residue here — the next MouseDown re-arms or the option-off teardown
    clears it; nulling it on a plain click keeps state tidy. }
  if (Button = mbLeft) and (FDragNode <> nil) then
    FDragNode := nil;

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
      draggedCol := FHeader.Columns.Items[FDragColumn] as TTyColumn;
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

  { ③f F2: Esc cancels an in-progress node drag (no move). Placed first so it can't
    disturb other Esc handling — when NOT dragging this is skipped and Esc falls
    through unchanged. }
  if (Key = VK_ESCAPE) and FDragActive then
  begin
    EndNodeDrag;
    Key := 0;
    Exit;
  end;

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

    { ←/→ move a NODE between slots, not a caret between characters, so by the criterion
      in §6.3 item 4 of plans/2026-08-04-rtl-mirroring-scope.md they are LAYOUT direction
      and they flip. Which physical key means "deeper" is the only thing that changes:
      children are drawn further along the reading direction, so it is → normally and ←
      when the tree reads right-to-left. Both are routed through one pair of methods so
      that flipping one and not the other -- a tree that collapses and never reopens --
      is not expressible here. }
    VK_RIGHT:
    begin
      if RtlLayout then KeyStepOut(cur) else KeyStepIn(cur);
      Key := 0;
    end;

    VK_LEFT:
    begin
      if RtlLayout then KeyStepIn(cur) else KeyStepOut(cur);
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
        rowH  := MulDiv(GetDefaultNodeHeight, Font.PixelsPerInch, 96);
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
        rowH  := MulDiv(GetDefaultNodeHeight, Font.PixelsPerInch, 96);
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
  col: TTyColumn;
begin
  if FHeader = nil then Exit;
  if (ColIndex < 0) or (ColIndex >= FHeader.Columns.Count) then Exit;

  col := FHeader.Columns.Items[ColIndex] as TTyColumn;

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

  Those slot widths and conditions are NOT restated here — they come from
  NodeCaptionSlots, the same call RenderTo's two caption paints make. There used to
  be a note here asking whoever edited this to keep it in step with three other
  places by hand; the walk is shared now, so the note would be false. The only
  arithmetic left below is the right-hand pad, which is this function's alone. }
function TTyTreeView.CellTextRect(Node: PTyTreeNode; Column: Integer;
  const ACellRect: TRect): TRect;
var
  PPI, effCol: Integer;
  isMain: Boolean;
  slots: TTyTreeCaptionSlots;
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

  { The cell band's own left IS the anchor here — this is the one consumer that is
    handed the cell rect directly, so it can never be looking at a different cell
    from the one it was asked about. }
  slots := NodeCaptionSlots(Node, ACellRect.Left, ACellRect.Right, PPI, isMain);
  Result.Left  := slots.CaptionX + slots.TextPad;
  { The walk's own far edge, not the cell's: mirrored they are different numbers, and
    using the cell's would open the editor across the chrome it must sit beside. }
  Result.Right := slots.CaptionRight - slots.TextPad;

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
  else
    DoGetText(Node, Result);
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
  FEndingEdit guards re-entry (a focus-loss commit can fire mid-teardown).
  OnEditingEnd(Cancel=False) fires last, ALWAYS — OnNewText is conditional on the
  text having changed, so it is not a usable "the editor closed" signal. }
procedure TTyTreeView.EndEditNode;
var
  endNode: PTyTreeNode;
  endCol:  Integer;
begin
  if FEndingEdit then Exit;
  if not FEditing then Exit;
  FEndingEdit := True;
  try
    endNode := FEditNode;
    endCol  := FEditColumn;
    if (FEditor.Text <> FEditOriginalText) and Assigned(FOnNewText) then
      FOnNewText(Self, FEditNode, FEditColumn, FEditor.Text);
    FinishEdit;
    { after FinishEdit: the edit state is already torn down, so a handler that
      re-opens an editor from here is not fighting a half-live one. }
    if Assigned(FOnEditingEnd) then FOnEditingEnd(Self, endNode, endCol, False);
  finally
    FEndingEdit := False;
  end;
end;

{ Discard the active edit: fire OnEditCancelled, then tear down (no commit). }
procedure TTyTreeView.CancelEdit;
var
  endNode: PTyTreeNode;
  endCol:  Integer;
begin
  if FEndingEdit then Exit;
  if not FEditing then Exit;
  FEndingEdit := True;
  try
    endNode := FEditNode;
    endCol  := FEditColumn;
    if Assigned(FOnEditCancelled) then
      FOnEditCancelled(Self, FEditNode, FEditColumn);
    FinishEdit;
    if Assigned(FOnEditingEnd) then FOnEditingEnd(Self, endNode, endCol, True);
  finally
    FEndingEdit := False;
  end;
end;

{ ══ LCL parity surface ═══════════════════════════════════════════════════════
  Everything below exists because the audit of our published members against
  C:/lazarus/lcl/comctrls.pp found it missing, differently named, or -- the bad
  case -- present under LCL's name with a different meaning. Each block cites the
  LCL declaration it mirrors. }

{ ── the LCL-shaped GetNodeAt ─────────────────────────────────────────────── }

function TTyTreeView.GetNodeAt(X, Y: Integer): PTyTreeNode;
var
  part: TTyTreeHitPart;
begin
  Result := GetNodeAtPoint(X, Y, part);
  { LCL answers nil for a point that is not on a node at all. GetNodeAtPoint
    already returns nil there, but it also reports hpHeaderSection/hpHeaderDivider
    with a nil node for the header band -- keep nil. }
end;

{ ── Selected: the current node (comctrls.pp:3778) ────────────────────────── }

function TTyTreeView.GetSelection: PTyTreeNode;
begin
  { LCL's Selected is nil when nothing is selected. FFocusedNode survives a
    ClearSelection (the caret stays where it was), so answer it only while it is
    actually selected; otherwise fall back to the first selected node, which is
    what a multi-select tree means by "the current one" after a range gesture. }
  Result := FFocusedNode;
  if (Result <> nil) and (nsSelected in Result^.States) then Exit;
  Result := GetFirstSelected;
end;

procedure TTyTreeView.SetSelection(AValue: PTyTreeNode);
begin
  if AValue = nil then
  begin
    ClearSelection;
    Exit;
  end;
  if AValue = FRoot then Exit;
  { Exclusive select + focus, which is what `Tree.Selected := N` means in LCL even
    with MultiSelect on. ClearSelection first so a multi-selection collapses to one. }
  if SelectedCount > 1 then ClearSelection;
  FocusedNode := AValue;
  if not (nsSelected in AValue^.States) then SetSelected(AValue, True);
end;

function TTyTreeView.GetSelections(AIndex: Integer): PTyTreeNode;
var
  n: PTyTreeNode;
  i: Integer;
begin
  Result := nil;
  if AIndex < 0 then Exit;
  i := 0;
  n := GetFirstSelected;
  while n <> nil do
  begin
    if i = AIndex then Exit(n);
    Inc(i);
    n := GetNextSelected(n);
  end;
end;

function TTyTreeView.GetLastSelected: PTyTreeNode;
var
  n: PTyTreeNode;
begin
  Result := nil;
  n := GetFirstSelected;
  while n <> nil do
  begin
    Result := n;
    n := GetNextSelected(n);
  end;
end;

{ ── the four switches under LCL's names (comctrls.pp:3697/:3662/:3701/:3694) ─ }

function TTyTreeView.GetRowSelect: Boolean;
begin
  Result := toFullRowSelect in FOptions;
end;

procedure TTyTreeView.SetRowSelect(AValue: Boolean);
begin
  if AValue then Options := FOptions + [toFullRowSelect]
  else           Options := FOptions - [toFullRowSelect];
end;

function TTyTreeView.GetMultiSelect: Boolean;
begin
  Result := toMultiSelect in FOptions;
end;

procedure TTyTreeView.SetMultiSelect(AValue: Boolean);
begin
  if AValue then Options := FOptions + [toMultiSelect]
  else           Options := FOptions - [toMultiSelect];
end;

function TTyTreeView.GetShowLines: Boolean;
begin
  Result := FShowTreeLines;
end;

procedure TTyTreeView.SetShowLines(AValue: Boolean);
begin
  SetShowTreeLines(AValue);
end;

function TTyTreeView.GetReadOnly: Boolean;
begin
  Result := not (toEditable in FOptions);
end;

procedure TTyTreeView.SetReadOnly(AValue: Boolean);
begin
  if AValue then Options := FOptions - [toEditable]
  else           Options := FOptions + [toEditable];
end;

{ ── ScrollBars (comctrls.pp:3777) ────────────────────────────────────────── }

procedure TTyTreeView.SetScrollBars(AValue: TScrollStyle);
begin
  if FScrollBars = AValue then Exit;
  FScrollBars := AValue;
  { A bar that is no longer permitted must give its offset back, or the content
    stays scrolled with nothing left to scroll it. UpdateScrollBars zeroes the
    offset of any bar it hides. }
  UpdateScrollBars;
  Invalidate;
end;

procedure TTyTreeView.SetHideSelection(AValue: Boolean);
begin
  if FHideSelection = AValue then Exit;
  FHideSelection := AValue;
  Invalidate;
end;

procedure TTyTreeView.SetShowSeparators(AValue: Boolean);
begin
  if FShowSeparators = AValue then Exit;
  FShowSeparators := AValue;
  Invalidate;
end;

{ ── per-node Visible (comctrls.pp:3179) ──────────────────────────────────── }

{ Like AdjustTotalHeight but starting at Node's PARENT, so Node's own TotalHeight
  is left intact. Hiding a node must not destroy the subtree total we add back
  when it is shown again. }
procedure TTyTreeView.AdjustAncestorsHeight(Node: PTyTreeNode; Delta: Integer);
var
  run, up: PTyTreeNode;
begin
  if (Node = nil) or (Delta = 0) then Exit;
  run := Node;
  while True do
  begin
    up := run^.Parent;
    if (up = nil) or (up = PTyTreeNode(Self)) then Break;
    if not (nsExpanded in up^.States) then Break;
    Inc(up^.TotalHeight, Delta);
    run := up;
  end;
end;

function TTyTreeView.GetNodeVisible(Node: PTyTreeNode): Boolean;
begin
  Result := (Node <> nil) and (nsVisible in Node^.States);
end;

procedure TTyTreeView.SetNodeVisible(Node: PTyTreeNode; AValue: Boolean);
var
  contrib: Integer;
begin
  if (Node = nil) or (Node = FRoot) then Exit;
  if AValue = (nsVisible in Node^.States) then Exit;

  { The node's screen contribution is its whole subtree total (NodeHeight when
    collapsed or childless). Take it off / put it back on the ancestor chain so
    ContentHeight, the scrollbars and the position cache all stay honest --
    RootNode^.TotalHeight - RootNode^.NodeHeight must equal the sum of NodeHeight
    over the nodes that actually paint. }
  contrib := Integer(Node^.TotalHeight);
  if AValue then
  begin
    Include(Node^.States, nsVisible);
    AdjustAncestorsHeight(Node, contrib);
  end
  else
  begin
    Exclude(Node^.States, nsVisible);
    AdjustAncestorsHeight(Node, -contrib);
    { A hidden node must not keep the caret or the selection: both would point at
      a row nothing draws, and keyboard nav would walk off it into nowhere. }
    if FFocusedNode = Node then FFocusedNode := nil;
    if nsSelected in Node^.States then InternalSetSelected(Node, False);
  end;
  InvalidateTreeLayout;
end;

{ ── per-node HasChildren, re-askable (comctrls.pp:3688 OnHasChildren) ────── }

function TTyTreeView.GetHasChildren(Node: PTyTreeNode): Boolean;
begin
  Result := (Node <> nil) and (nsHasChildren in Node^.States);
end;

procedure TTyTreeView.SetHasChildren(Node: PTyTreeNode; AValue: Boolean);
begin
  if (Node = nil) or (Node = FRoot) then Exit;
  if AValue = (nsHasChildren in Node^.States) then Exit;
  if AValue then
    Include(Node^.States, nsHasChildren)
  else
  begin
    { Dropping the flag on an expanded node would leave its children on screen with
      no way to collapse them -- the expander is gone. Collapse first. }
    if nsExpanded in Node^.States then SetExpanded(Node, False);
    Exclude(Node^.States, nsHasChildren);
  end;
  InvalidateTreeLayout;
end;

{ ── writable scroll position (comctrls.pp:3698-3699/:3759/:3787) ─────────── }

function TTyTreeView.GetScrolledTop: Integer;
begin
  Result := -FOffsetY;    { LCL counts pixels scrolled AWAY; FOffsetY is <= 0 }
end;

procedure TTyTreeView.SetScrolledTop(AValue: Integer);
var
  viewH, minOff: Integer;
begin
  if AValue < 0 then AValue := 0;
  FOffsetY := -AValue;
  { Same clamp ScrollIntoView applies, so a restore of a stale value cannot park
    the viewport past the end of the content. }
  viewH  := MulDiv(ClientHeight, 96, Font.PixelsPerInch);
  minOff := viewH - FRangeY;
  if minOff > 0 then minOff := 0;
  if FOffsetY < minOff then FOffsetY := minOff;
  if FOffsetY > 0 then FOffsetY := 0;
  UpdateScrollBars;
  Invalidate;
  RepositionEditor;
end;

function TTyTreeView.GetScrolledLeft: Integer;
begin
  Result := -FOffsetX;
end;

procedure TTyTreeView.SetScrolledLeft(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  FOffsetX := -AValue;
  if FOffsetX > 0 then FOffsetX := 0;
  UpdateScrollBars;   { clamps against FRangeX and the viewport width }
  Invalidate;
  RepositionEditor;
end;

function TTyTreeView.GetTopItem: PTyTreeNode;
var
  nodeTop: Integer;
begin
  Result := GetNodeAtOffset(-FOffsetY, nodeTop);
end;

procedure TTyTreeView.SetTopItem(AValue: PTyTreeNode);
var
  n: PTyTreeNode;
  accTop: Integer;
begin
  if (AValue = nil) or (AValue = FRoot) then Exit;
  if not (nsVisible in AValue^.States) then Exit;
  accTop := 0;
  n := GetFirstVisibleNoInit;
  while n <> nil do
  begin
    if n = AValue then
    begin
      ScrolledTop := accTop;
      Exit;
    end;
    Inc(accTop, n^.NodeHeight);
    n := GetNextVisibleNoInit(n);
  end;
  { not reachable in the current visible order (collapsed ancestor) -- no scroll }
end;

function TTyTreeView.GetBottomItem: PTyTreeNode;
var
  viewH, y, nodeTop: Integer;
  n: PTyTreeNode;
begin
  viewH := MulDiv(ClientHeight, 96, Font.PixelsPerInch);
  y := -FOffsetY + viewH - 1;
  if y < 0 then y := 0;
  Result := GetNodeAtOffset(y, nodeTop);
  if Result <> nil then Exit;
  { The viewport ends past the content (short tree / scrolled to the end), so the
    last node in visible order IS the bottom one. }
  n := GetFirstVisibleNoInit;
  while n <> nil do
  begin
    Result := n;
    n := GetNextVisibleNoInit(n);
  end;
end;

{ ── per-node geometry (comctrls.pp:3096-3102) ────────────────────────────── }

function TTyTreeView.DisplayRect(Node: PTyTreeNode; TextOnly: Boolean;
  out ARect: TRect): Boolean;
var
  cell: TRect;
  col: Integer;
begin
  ARect  := Rect(0, 0, 0, 0);
  Result := False;
  if Node = nil then Exit;
  col := NoColumn;
  if (FHeader <> nil) and (FHeader.Columns.Count > 0) then col := FHeader.MainColumn;
  if not GetCellRect(Node, col, cell) then Exit;
  if TextOnly then
    ARect := CellTextRect(Node, col, cell)
  else
    { the whole ROW, not just the main cell -- LCL's DisplayRect(False) spans the
      control width }
    ARect := Rect(ContentRect.Left, cell.Top, ContentRect.Right, cell.Bottom);
  Result := True;
end;

function TTyTreeView.DisplayTextLeft(Node: PTyTreeNode; out ALeft: Integer): Boolean;
var
  r: TRect;
begin
  ALeft  := 0;
  Result := DisplayRect(Node, True, r);
  if Result then ALeft := r.Left;
end;

function TTyTreeView.DisplayExpandSignRect(Node: PTyTreeNode; out ARect: TRect): Boolean;
var
  cell: TRect;
  col, gSz, slotBaseX, rowH, PPI: Integer;
  slots: TTyTreeCaptionSlots;
begin
  ARect  := Rect(0, 0, 0, 0);
  Result := False;
  if Node = nil then Exit;
  if not (FShowButtons and (nsHasChildren in Node^.States)) then Exit;
  col := NoColumn;
  if (FHeader <> nil) and (FHeader.Columns.Count > 0) then col := FHeader.MainColumn;
  if not GetCellRect(Node, col, cell) then Exit;

  { The expander slot comes from the shared walk (the same one RenderTo's btnRect
    block reads), anchored on the cell this node's main column actually occupies;
    only the centred-square sizing is this function's own. }
  PPI       := Font.PixelsPerInch;
  rowH      := cell.Bottom - cell.Top;
  slots     := NodeCaptionSlots(Node, cell.Left, cell.Right, PPI, True);
  gSz       := slots.ButtonSlotW;
  if rowH < gSz then gSz := rowH;
  slotBaseX := slots.ButtonSlotX + (slots.ButtonSlotW - gSz) div 2;
  ARect := Rect(slotBaseX, cell.Top + (rowH - gSz) div 2,
                slotBaseX + gSz, cell.Top + (rowH - gSz) div 2 + gSz);
  Result := True;
end;

function TTyTreeView.GetNodeWithExpandSignAt(X, Y: Integer): PTyTreeNode;
var
  part: TTyTreeHitPart;
  n: PTyTreeNode;
begin
  Result := nil;
  n := GetNodeAtPoint(X, Y, part);
  if (n <> nil) and (part = hpButton) then Result := n;
end;

{ ── GetHitTestInfoAt (comctrls.pp:3715, THitTest at :41) ─────────────────── }

function TTyTreeView.GetHitTestInfoAt(X, Y: Integer): THitTests;
var
  part: TTyTreeHitPart;
  n: PTyTreeNode;
  r: TRect;
begin
  Result := [];
  n := GetNodeAtPoint(X, Y, part);
  if n = nil then
  begin
    { LCL distinguishes "above every row" / "below every row" / neither. }
    r := ContentRect;
    if Y < r.Top then Include(Result, htAbove)
    else if Y >= r.Bottom then Include(Result, htBelow)
    else if X < r.Left then Include(Result, htToLeft)
    else if X >= r.Right then Include(Result, htToRight)
    else Include(Result, htNowhere);
    Exit;
  end;

  { On a node: htOnItem is LCL's "the point is on this item's row" and coexists
    with the more specific part -- which is exactly the expressiveness the
    single-valued TTyTreeHitPart cannot reach. }
  Include(Result, htOnItem);
  case part of
    hpButton:   Include(Result, htOnButton);
    hpImage:    Include(Result, htOnIcon);
    hpLabel:    Include(Result, htOnLabel);
    hpIndent:   Include(Result, htOnIndent);
    hpCheckBox: Include(Result, htOnStateIcon);
  else
    ;
  end;
  { Right of the caption but still in the row: LCL reports htOnItem + htOnRight. }
  if (part = hpLabel) and DisplayRect(n, True, r) and (X >= r.Right) then
    Include(Result, htOnRight);
end;

{ ── AlphaSort (comctrls.pp:3709) ─────────────────────────────────────────── }

function TTyTreeView.AlphaSort(Node: PTyTreeNode): Boolean;
var
  saved: TTyTreeCompareEvent;
begin
  { Borrow the existing sort engine, temporarily standing in for the app's compare
    handler. Restoring it in a finally keeps AlphaSort from being a way to lose a
    handler the app installed. }
  saved := FOnCompareNodes;
  FOnCompareNodes := @AlphaCompare;
  try
    if Node = nil then
      SortTree(NoColumn, sdAscending)
    else
      Sort(Node, NoColumn, sdAscending, False);
  finally
    FOnCompareNodes := saved;
  end;
  Result := True;
end;

function TTyTreeView.CustomSort(SortProc: TTyTreeNodeCompare; Node: PTyTreeNode): Boolean;
var
  saved: TTyTreeCompareEvent;
begin
  Result := False;
  if SortProc = nil then Exit;
  FCustomSortProc := SortProc;
  saved := FOnCompareNodes;
  FOnCompareNodes := @CustomSortCompare;
  try
    if Node = nil then
      SortTree(NoColumn, sdAscending)
    else
      Sort(Node, NoColumn, sdAscending, False);
  finally
    FOnCompareNodes := saved;
    FCustomSortProc := nil;
  end;
  Result := True;
end;

procedure TTyTreeView.CustomSortCompare(Sender: TTyTreeView; Node1, Node2: PTyTreeNode;
  Column: Integer; var CompareResult: Integer);
begin
  if Assigned(FCustomSortProc) then
    CompareResult := FCustomSortProc(Node1, Node2)
  else
    CompareResult := 0;
end;

procedure TTyTreeView.AlphaCompare(Sender: TTyTreeView; Node1, Node2: PTyTreeNode;
  Column: Integer; var CompareResult: Integer);
begin
  { The MAIN-column text the painter shows -- the same path OnGetText feeds, so
    what the user reads is what gets sorted. UTF8CompareText is case-insensitive
    and UTF-8 aware; CompareText would mis-order anything non-ASCII. }
  CompareResult := UTF8CompareText(GetNodeSearchText(Node1), GetNodeSearchText(Node2));
end;

{ ── OnChanging: the veto in front of a selection move (comctrls.pp:3669) ─── }

function TTyTreeView.DoChanging(Node: PTyTreeNode): Boolean;
var
  allowed: Boolean;
begin
  Result := True;
  if FSuppressChanging then Exit;          { already asked, this same gesture }
  if not Assigned(FOnChanging) then Exit;
  allowed := True;
  FOnChanging(Self, Node, allowed);
  Result := allowed;
end;

{ AutoExpand (comctrls.pp:3654): the node that gains focus opens, the one that
  loses it closes. The previous node is left alone when the new focus is inside
  its subtree -- otherwise walking INTO a folder would immediately shut it. }
procedure TTyTreeView.ApplyAutoExpand(APrev, ANew: PTyTreeNode);
begin
  if not FAutoExpand then Exit;
  if (APrev <> nil) and (APrev <> ANew) and (nsExpanded in APrev^.States) and
     not IsDescendant(ANew, APrev) then
    SetExpanded(APrev, False);
  if (ANew <> nil) and (nsHasChildren in ANew^.States) and
     not (nsExpanded in ANew^.States) then
    SetExpanded(ANew, True);
end;

initialization
  RegisterClass(TTyTreeView);

end.
