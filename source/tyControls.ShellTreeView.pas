unit tyControls.ShellTreeView;
{$mode objfpc}{$H+}
{ TTyShellTreeView -- a file-system-backed TTyTreeView.

  Design: docs/superpowers/specs/2026-07-11-phase7-shell-filedialogs-design.md
  Plan  : docs/superpowers/plans/2026-07-11-phase7-shelltreeview.md

  This is a LAZY directory tree. By default its roots are the portable "places"
  from tyControls.FileSystem.TyFsRoots (drives on Windows; '/', home, mounted
  volumes on Unix), and Root scopes it to a single directory instead. A node's
  children are enumerated on expand via TyFsReadDirectory(path, '*', ObjectTypes);
  ObjectTypes decides whether files appear as leaves alongside the folders.

  The shell behaviour lives in OVERRIDES of the base's virtuals (DoGetText,
  DoInitNode, DoExpanding, DoGetImageIndex, DoTreeChange), never in the published
  event slots: a node stores a single Integer index into an FNodes table,
  DoGetText renders the leaf name (or a root's curated Display), DoInitNode stamps
  the has-children arrow via the cheap TyFsHasEntry probe, DoExpanding populates
  children, DoGetImageIndex picks a drive/folder/file glyph, and DoTreeChange
  caches the focused path + fires OnPathChange (the seam a file dialog uses to
  drive its file list off the tree selection). Each calls inherited, so an
  application handler still runs.

  It reuses the tree theme tokens (GetStyleTypeKey = 'TyTreeView', inherited);
  zero new theme tokens. }

interface

uses
  Classes, SysUtils, TypInfo, Graphics, Controls, ImgList,
  LazFileUtils,
  BGRABitmap, BGRABitmapTypes,
  tyControls.TreeView, tyControls.ImageCollection, tyControls.LCLImageList,
  tyControls.FileSystem,
  tyControls.ShellListView;

const
  { The pixel edge of the tree's icon list. The 128px BGRA masters are rendered
    down into this; 16px matches the default Indent slot and the 22px row height. }
  TyShellTreeIconSize = 16;
  { The glyph indices in FImages, in the order BuildGlyphs adds them. }
  TyShellTreeFolderGlyph = 0;
  TyShellTreeDriveGlyph  = 1;
  TyShellTreeFileGlyph   = 2;

  { The mask a directory tree enumerates with. It filters FILES only (folders are
    always kept), and a tree that shows files shows all of them -- filtering the
    leaves is what OnAddItem is for. }
  TyShellTreeMask = '*';

  { UseBuiltinIcons' published default. True, matching LCL (shellctrls.pas:135). }
  TyShellTreeUseBuiltinIcons = True;

  { The ETyShellInvalidPath messages. DEVELOPER diagnostics (you assigned a path
    this tree cannot show), so they stay English rather than becoming
    resourcestrings: only tyControls.StrConsts is wired into the runtime's
    per-unit TranslateUnitResourceStrings call, and the i18n spec already keeps
    technical errors (the CSS-syntax family) English-only. }
  TyShellInvalidPathMsg = 'TTyShellTreeView.Directory: cannot select "%s" -- %s';
  TyShellInvalidRootMsg = 'TTyShellTreeView.Root: "%s" is not an existing directory';

type
  { Why a path assignment did not land on its target.

    This exists because the failure used to be UNOBSERVABLE: SelectPath returned
    nothing and Directory read back the OLD path, so "the path is wrong" and "the
    path is right and this tree simply has nothing to show" produced byte-identical
    results. LCL raises a typed EInvalidPath instead (shellctrls.pas:428 declares
    it; SetRoot:625 and SetPath:1549/1561/1580/1604 raise it) -- catchable, but it
    carries only a message, so an app that wants to BRANCH on the reason has to
    parse English. The enum is the branchable half; ETyShellInvalidPath below is
    the catchable half. }
  TTyShellPathError = (
    speNone,          { the target node was reached and focused }
    speEmptyPath,     { '' or whitespace -- nothing was asked for, nothing happened }
    speNoSuchPath,    { no such directory on this machine (the typo case) }
    speNoRoot,        { it exists, but no seeded root is a prefix of it -- e.g.
                        SelectPath before PopulateRoots, a drive TyFsRoots does not
                        enumerate, or a path outside a scoped Root }
    speUnreachable);  { a root matched but a segment was not enumerable
                        (permissions, or hidden while ShowHidden is False);
                        focus was left on the DEEPEST reachable ancestor }

  { Raised by the published Directory / Path / Root setters -- and only by them. A
    property write has no return channel, so silence there is unrecoverable;
    SelectPath, which does have one, reports through Boolean + LastPathError and
    never raises. }
  ETyShellInvalidPath = class(Exception);

  { When a node's children are re-read from disk.

    LCL's TExpandCollapseMode (shellctrls.pas:48-52) has a third value,
    ecmCollapseAndClear (drop the children on COLLAPSE). It is deliberately absent
    here rather than present and inert: TTyTreeView has no protected collapse seam
    -- SetExpanded is a non-virtual private setter and the only collapse hooks are
    the published OnCollapsing / OnCollapsed slots, which belong to the
    application. Offering an enum value that silently did nothing would be the
    exact defect this control has just finished removing. See docs. }
  TTyExpandCollapseMode = (
    ecmRefreshedExpanding,  { re-read the children on every expand (LCL's default) }
    ecmKeepChildren);       { keep an already-built child list; only a never-yet-
                              expanded node reads from disk }

  { One row of the node-data table: a node's Integer node-data is an index into it.
    IsDir is carried rather than re-probed because it decides the glyph, the
    has-children arrow and GetPathFromNode's trailing delimiter -- all of which run
    per paint, where a DirectoryExists() call per node would be a disk hit. }
  TTyShellNodeInfo = record
    Path:  string;
    IsDir: Boolean;
  end;

  { ===================================================================
    TTyShellTreeView
    =================================================================== }
  { The concrete descendant of the TTyShellTreeLink seam declared in
    tyControls.ShellListView -- see that declaration for why the abstract class
    lives over there rather than here. }
  TTyShellTreeView = class(TTyShellTreeLink)
  private
    FNodes:        array of TTyShellNodeInfo;   { node-data index -> path + kind }
    FRoots:        TTyFsRootArray;    { the places seeded by PopulateRoots (for their Display) }
    FRoot:         string;            { '' = the machine places; else the one scoped directory }
    FObjectTypes:  TTyFsObjectTypes;  { what an enumeration keeps; default [fotFolders] }
    FShowHidden:   Boolean;           { a view of the fotHidden bit in FObjectTypes }
    FFileSortType: TTyFsFileSortType;
    FExpandMode:   TTyExpandCollapseMode;
    FUseBuiltinIcons: Boolean;
    FIcons:        TTyImageCollection;{ owned; the 128px BGRA masters }
    { owned; the masters, down-rendered into something TTyTreeView.Images accepts.
      This used to be a hand-filled TImageList at a hardcoded 16px -- the shape that showed the
      library needed a general bridge in the first place. It is now TTyLCLImageList, which
      renders the same masters through the same TTyVirtualImageList every other consumer here
      uses, keeps the slots in Names order (so the TyShellTree*Glyph constants below stay
      valid), and refills itself if the masters change. MultiResolution is OFF because a tree
      paints via Images.Draw -> GetResolution(FWidth) and never pulls another width. }
    FNames:        TTyVirtualImageList;
    FImages:       TTyLCLImageList;
    FSelectedPath: string;            { the focused directory, cached from DoTreeChange }
    FOnPathChange: TNotifyEvent;
    FOnAddItem:    TTyFsAddItemEvent;
    FOnSortCompare: TTyFsCompareEvent;
    FLastPathError: TTyShellPathError;
    FShellListView: TTyShellListView;
    { >0 while this control is pushing a change INTO its companion list. The list
      pushes back on load, so without it the pair would recurse forever -- LCL
      guards the same cascade with FLockUpdate (shellctrls.pas:2003-2011). }
    FLinkLock:      Integer;
    { >0 while a tree walk (SelectPath / UpdateView / Refresh) is holding node
      pointers. Any refresh requested during that window is queued in
      FPendingRefresh and applied when the outermost walk unwinds -- refreshing in
      the middle would free the very nodes the walk is standing on. }
    FBusy:           Integer;
    FPendingRefresh: Boolean;
    FDraining:       Boolean;

    { Build the fixed-palette folder + drive + file glyphs and assign them to Images. }
    procedure BuildGlyphs;
    { node data = one Integer index into FNodes. }
    function  AddPathNode(AParent: PTyTreeNode; const AFullPath: string;
      AIsDir: Boolean): PTyTreeNode;
    { The one directory read: enumerate + OnAddItem veto + FileSortType ordering. }
    function  ReadEntries(const APath: string): TTyFsEntryArray;
    { Lazy child fill: enumerate NodePath(Node)'s entries. }
    procedure PopulateChildren(Node: PTyTreeNode);
    { Drop ANode's cached children and re-stamp its has-children arrow from the
      cheap probe. SetChildCount(_, 0) also clears nsHasChildren, and SetExpanded
      bails on a node that does not carry it -- so without the re-stamp a later
      expand silently does nothing at all. }
    procedure ResetBranch(ANode: PTyTreeNode);
    { FNodes is append-only, so without this every refresh would leak the whole
      previous child set into it. Re-seeds the table from the nodes that SURVIVED
      and re-stamps their node data. }
    procedure CompactNodes;
    { The materialised node whose path is APath, or nil. Unlike SelectPath this
      expands nothing and touches no disk: it only looks at what is already there. }
    function  FindNode(const APath: string): PTyTreeNode;
    function  NodeIsDir(Node: PTyTreeNode): Boolean;
    { Resolve a possibly root-relative path to an absolute one (see SetPath). }
    function  ResolveRelative(const AValue: string): string;
    function  GetPath: string;
    procedure SetPath(const AValue: string);
    procedure SetRoot(const AValue: string);
    procedure SetObjectTypes(AValue: TTyFsObjectTypes);
    procedure SetShowHidden(AValue: Boolean);
    procedure SetFileSortType(AValue: TTyFsFileSortType);
    procedure SetOnSortCompare(AValue: TTyFsCompareEvent);
    procedure SetUseBuiltinIcons(AValue: Boolean);
    procedure SetShellListView(AValue: TTyShellListView);
    { Push the focused directory into the linked list, guarded against the
      push-back it will provoke. }
    procedure PushToList;
    { The published Directory setter (see ETyShellInvalidPath). }
    procedure SetDirectory(const AValue: string);
    { Apply a refresh that was queued while a walk was in progress. }
    procedure DrainPendingRefresh;
  protected
    { The TTyShellTreeLink seam the companion list drives this control through. }
    procedure ShellLinkSelect(const APath: string); override;
    procedure ShellLinkUpdate(const AStartDir: string); override;
    { Nils a link whose partner is being freed -- otherwise the next selection
      walks a dead pointer. }
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    { The shell behaviour, as OVERRIDES of the base's virtuals.

      These five used to be handlers wired to the PUBLISHED OnGetText / OnInitNode /
      OnExpanding / OnGetImageIndex / OnChange slots in the constructor, so the shell and
      the application were fighting over one slot each: assign OnGetText on a shell tree
      and it stopped showing filenames, with nothing to say why. As overrides the events
      belong to the app, which is how LCL's TShellTreeView is built. Each calls inherited,
      so an app handler runs AFTER the shell has filled its answer in and can replace it. }
    procedure DoGetText(Node: PTyTreeNode; var AText: string); override;
    procedure DoInitNode(AParent, Node: PTyTreeNode;
      var AStates: TTyNodeInitStates); override;
    procedure DoExpanding(Node: PTyTreeNode; var AAllowed: Boolean); override;
    procedure DoGetImageIndex(Node: PTyTreeNode; AKind: TTyVTImageKind; AColumn: Integer;
      var AGhosted: Boolean; var AIndex: Integer); override;
    procedure DoTreeChange(Node: PTyTreeNode); override;
    { The RAW absolute path a node maps to -- no trailing delimiter, whatever the
      node is. This is the internal form every comparison in this unit uses;
      GetPathFromNode is the public, LCL-shaped one. Protected so a subclass/test
      can observe the node<->path mapping. }
    function  NodePath(Node: PTyTreeNode): string;
  public
    constructor Create(AOwner: TComponent); override;
    destructor  Destroy; override;

    { The platform's base path: '' on Windows (where the places are the drives),
      '/' on Unix. LCL: shellctrls.pas:125 / 964-978. }
    class function GetBasePath: string;
    { The effective root, delimiter-terminated when non-empty: Root when one is
      set, else GetBasePath. LCL: shellctrls.pas:126 / 980-987. }
    function  GetRootPath: string;
    { A static directory enumerator other classes can reuse, the way LCL's
      GetFilesInDir is reused (shellctrls.pas:127-129). Ours returns the same
      TTyFsEntryArray every view in this family is backed by, rather than filling a
      caller-supplied TStrings -- the records carry Size / Modified / Attr /
      TypeName, which a list of strings cannot. }
    class function GetFilesInDir(const ABaseDir, AMask: string;
      AObjectTypes: TTyFsObjectTypes;
      AFileSortType: TTyFsFileSortType = fstNone;
      ACaseSensitivity: TTyMaskCaseSensitivity = mcsCaseInsensitive): TTyFsEntryArray;

    { The absolute path ANode maps to, with a trailing delimiter when it is a
      DIRECTORY -- LCL's GetPathFromNode contract (shellctrls.pas:131 / 1195-1207).
      '' for nil. This is the public node -> path mapping: before it existed only
      the FOCUSED path was reachable from outside the class, so an app could not
      resolve a path from a draw handler, a drag source or a multi-selection. }
    function  GetPathFromNode(ANode: PTyTreeNode): string;

    { False: this tree owns its data. It builds its own nodes from the filesystem and
      renders their captions in DoGetText, so the base's Items collection has nothing to
      say here. Without this override, filling Items on a shell tree would still fail --
      the item layer would rebuild the tree, and then PopulateRoots would walk into the
      virtual-structure gate and raise from AddChild. Loud, but pointing at the wrong
      cause. Refusing here means RebuildFromItems says so in one sentence, and the
      design-time node editor never attaches to this control in the first place. }
    function  SupportsItemModel: Boolean; override;

    { Clear the tree and re-seed it: one node per TyFsRoots place, or the single
      Root directory when one is set. }
    procedure PopulateRoots;
    { Re-enumerate the tree against the current filesystem and settings, preserving
      which nodes are expanded and where the focus sits.

      AStartDir limits the refresh to that node's subtree (LCL's
      UpdateView(AStartDir), shellctrls.pas:134); '' refreshes every expanded node
      from the roots down. A path that names no MATERIALISED node refreshes
      nothing -- there is nothing of it on screen to bring up to date.

      This is the middle ground between "do nothing" (what ShowHidden used to do)
      and PopulateRoots (which throws the whole tree away, focus included). Only
      nodes that were ALREADY expanded are re-read -- a collapsed node was never
      enumerated, so there is nothing of it to refresh. The nodes at the top of the
      refreshed scope keep their handles; every node below them is re-created,
      which is unavoidable (the point of a refresh is that the child set may have
      changed) and is why this is a method you call, not something that happens
      behind your back.

      Focus is restored by PATH, not by pointer, and degrades: if the focused
      directory is no longer visible (you just turned ShowHidden off while standing
      under a hidden ancestor) the focus lands on the deepest ancestor that IS
      still reachable, rather than being stranded on a freed node or lost.

      Called during a walk (from an OnPathChange / OnExpanding handler, say), it
      queues itself instead and runs when the walk unwinds. }
    procedure UpdateView(const AStartDir: string = '');
    { Re-read ONE node's children, leaving the rest of the tree alone; nil re-seeds
      the roots (LCL: shellctrls.pas:133 / 1209-1247). UpdateView is the whole-tree
      version -- after the app itself creates or deletes a folder, this is the
      cheap way to bring just that branch up to date. }
    procedure Refresh(ANode: PTyTreeNode); overload;
    { The focused directory (cached from the last change), or '' when none. }
    function  SelectedPath: string;
    { Reveal APath: expand from the containing root down to the target node and
      focus it (which caches the path + fires OnPathChange).

      Returns True only when the TARGET itself was reached; False otherwise, with
      LastPathError saying which of the four ways it went wrong. It never raises
      -- a caller with a return channel does not need an exception, and a file
      dialog resolving a path the user typed is not an exceptional event. On
      speUnreachable the focus is still moved, to the deepest reachable ancestor. }
    function  SelectPath(const APath: string): Boolean;
    { Why the last SelectPath / Directory / Path write did not reach its target
      (speNone after a successful one). Read-only: nothing but a path assignment
      writes it. }
    property LastPathError: TTyShellPathError read FLastPathError;
    { The selection under LCL's name and LCL's contract: reading appends a trailing
      path delimiter for a directory, and writing accepts an absolute path OR one
      relative to GetRootPath (shellctrls.pas:142).

      PUBLIC and not published on purpose: Directory is the same selection with the
      raw, undelimited value this library has always returned, and two published
      names over one piece of state would put it in every .lfm twice and give the
      Object Inspector two rows that overwrite each other. This exists so ported
      code that says `Tree.Path := X` compiles and means what LCL means. }
    property Path: string read GetPath write SetPath;
  published
    { The selection as a path. Reading returns SelectedPath (raw, no trailing
      delimiter); writing reveals + focuses it.

      BREAKING (deliberate): a write that cannot reach its target now raises
      ETyShellInvalidPath instead of doing nothing. A property write has no
      return value, so the old no-op left the caller holding a Directory that
      silently still read back the PREVIOUS path -- indistinguishable from
      success. Suppressed under csLoading/csDesigning so a stale path in a .lfm
      cannot break streaming or take the IDE down with it, which is the same
      carve-out LCL makes (shellctrls.pas:621-624). Assigning '' remains a
      silent no-op: no path was asked for, so none failed.

      Use SelectPath when you would rather test a Boolean than catch. }
    property Directory: string read SelectedPath write SetDirectory;
    { Scope the whole tree to one directory. '' (the default) means the machine-wide
      TyFsRoots places, which is all this control could ever show before -- so a
      chooser confined to a project folder or a document root was impossible without
      subclassing. Writing it rebuilds the tree; a path that does not exist raises
      ETyShellInvalidPath (outside csLoading/csDesigning), like LCL's SetRoot
      (shellctrls.pas:625). }
    property Root: string read FRoot write SetRoot;
    { Which kinds of entry the tree enumerates. Default [fotFolders] -- LCL's
      default too (shellctrls.pas:138), and what this control has always done.
      Adding fotFiles gives the classic Explorer left pane, with files as leaves
      that carry no expand arrow. Writing it re-enumerates the already-expanded
      nodes IMMEDIATELY (see UpdateView). fotHidden and ShowHidden are two views of
      one bit and stay in step. }
    property ObjectTypes: TTyFsObjectTypes read FObjectTypes write SetObjectTypes
      default [fotFolders];
    { Whether hidden entries are enumerated -- the fotHidden bit of ObjectTypes
      under its own name. Writing it re-enumerates immediately; it used to be
      flag-only, which meant the setting appeared to do nothing until some node
      happened to be re-expanded. LCL refreshes on the same kind of write
      (TCustomShellTreeView.SetObjectTypes -> UpdateView, shellctrls.pas:687). }
    property ShowHidden: Boolean read FShowHidden write SetShowHidden default False;
    { How a node's children are ordered. Default fstNone (LCL's default too,
      shellctrls.pas:140) = the raw filesystem order FindFirst produced, which is
      roughly alphabetical on NTFS and effectively arbitrary on ext4. fstCustom
      defers to OnSortCompare. Writing it re-enumerates. }
    property FileSortType: TTyFsFileSortType read FFileSortType write SetFileSortType
      default fstNone;
    { When a node re-reads its children. Default ecmRefreshedExpanding, matching
      LCL: every expand re-enumerates, so folders created or deleted since the last
      look appear. ecmKeepChildren is the behaviour this control used to be
      hard-wired to -- a directory was enumerated exactly ONCE per control lifetime
      and never noticed a change again. }
    property ExpandCollapseMode: TTyExpandCollapseMode read FExpandMode write FExpandMode
      default ecmRefreshedExpanding;
    { Whether the control's own folder/drive/file glyphs are used. Off detaches the
      built-in Images list, which is how a text-only tree (or one driven purely by
      an app's own list) is asked for -- previously the only route was to overwrite
      Images after construction, and there was no way to ask for no icons at all.
      LCL: shellctrls.pas:135. }
    property UseBuiltinIcons: Boolean read FUseBuiltinIcons write SetUseBuiltinIcons
      default TyShellTreeUseBuiltinIcons;
    { Fires whenever the focused directory changes (SelectedPath is the new path). }
    property OnPathChange: TNotifyEvent read FOnPathChange write FOnPathChange;
    { Per-entry veto, raised once for every entry a node's enumeration produced: set
      ACanAdd False to drop it. The only filter before this was the coarse hidden
      attribute, so hiding .git, a system junction or a symlink loop was impossible.
      LCL: shellctrls.pas:143. }
    property OnAddItem: TTyFsAddItemEvent read FOnAddItem write FOnAddItem;
    { A comparator over two RAW entries. Assigning it switches FileSortType to
      fstCustom and re-enumerates, exactly as LCL's SetOnSortCompare does
      (shellctrls.pas:693). The ancestor's OnCompareNodes compares NODES, i.e.
      rendered text -- ordering by extension, date or natural-numeric needs the
      file records, which is what this hands over. }
    property OnSortCompare: TTyFsCompareEvent read FOnSortCompare write SetOnSortCompare;
    { A companion shell list, assignable in the Object Inspector: selecting a
      folder here loads it into the list. Without it the canonical two-control file
      browser could not be assembled in the designer at all, and every host had to
      hand-write the OnPathChange -> Directory plumbing. LCL: shellctrls.pas:139,
      pushed from DoSelectionChanged (1141-1163) and SetRoot (641-642). }
    property ShellListView: TTyShellListView read FShellListView write SetShellListView;
  end;

implementation

{ ---------------------------------------------------------------------------
  Lifecycle
  --------------------------------------------------------------------------- }

constructor TTyShellTreeView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  FRoot         := '';
  FObjectTypes  := [fotFolders];
  FShowHidden   := False;
  FFileSortType := fstNone;
  FExpandMode   := ecmRefreshedExpanding;
  FUseBuiltinIcons := TyShellTreeUseBuiltinIcons;
  SetLength(FNodes, 0);

  { node data = one Integer index into FNodes; no managed types in raw node memory. }
  NodeDataSize    := SizeOf(Integer);
  { No published event slot is claimed here any more -- the shell behaviour is in the
    DoXxx overrides, leaving all five events to the application. }

  { A 16px glyph needs a little more than the default 18px row; HotTrack + the
    (already-default) ShowRoot give root nodes their own expand triangle. }
  DefaultNodeHeight := 22;
  HotTrack          := True;

  BuildGlyphs;
  PopulateRoots;
end;

destructor TTyShellTreeView.Destroy;
begin
  { FImages/FIcons are created ownerless (see BuildGlyphs). Free FImages first --
    its FreeNotification nils the inherited Images reference before we drop it. }
  FImages.Free;
  FNames.Free;
  FIcons.Free;
  inherited Destroy;
end;

{ Build a folder, a drive and a file glyph as 128px BGRA masters in a private
  TTyImageCollection, render them down into a plain LCL TImageList, and assign
  that list to the inherited Images.

  WHY TWO OBJECTS: the tree paints its icons from a plain TImageList (Images:
  TImageList, drawn via TImageList.Draw); a TTyVirtualImageList is a TComponent,
  not a TImageList, so -- unlike TTyShellListView, whose base takes a virtual
  list -- it cannot be assigned to Images without editing tyControls.TreeView
  (forbidden). We therefore author the masters in a TTyImageCollection (the 128px
  BGRA + fixed-palette contract) and bridge each into the TImageList.

  THEME EXEMPTION (deliberate, documented, consistent with TTyShellListView):
  these glyphs use a FIXED tasteful palette, not theme tokens. They are CONTENT
  (a folder vs. a drive vs. a file), not control chrome, and the constructor runs
  before the Controller/theme is resolved. An app that wants themed icons can
  assign its own Images, or turn UseBuiltinIcons off. }
procedure TTyShellTreeView.BuildGlyphs;
const
  G = 128;   { master edge, px }

  function Shade(const C: TBGRAPixel; AFactor: Single): TBGRAPixel;
  begin
    Result := BGRA(Round(C.red * AFactor), Round(C.green * AFactor),
                   Round(C.blue * AFactor), C.alpha);
  end;

  { A manila folder: back tab + body + a soft top lip. }
  procedure AddFolder(const AName: string; ABody: TBGRAPixel);
  var
    bmp: TBGRABitmap;
  begin
    bmp := TBGRABitmap.Create(G, G, BGRAPixelTransparent);
    try
      bmp.FillRoundRectAntialias(8, 20, 60, 46, 6, 6, Shade(ABody, 0.82));   { tab }
      bmp.FillRoundRectAntialias(8, 34, 120, 112, 8, 8, ABody);             { body }
      bmp.FillRectAntialias(8, 34, 120, 42, BGRA(255, 255, 255, 40));       { top lip }
      FIcons.AddBitmap(AName, bmp);
    finally
      bmp.Free;
    end;
  end;

  { An external-drive chassis: rounded box + a highlight band, a media slot and a
    small green activity LED. }
  procedure AddDrive(const AName: string; ABody: TBGRAPixel);
  var
    bmp: TBGRABitmap;
  begin
    bmp := TBGRABitmap.Create(G, G, BGRAPixelTransparent);
    try
      bmp.FillRoundRectAntialias(14, 40, 114, 100, 10, 10, ABody);            { chassis }
      bmp.FillRectAntialias(14, 40, 114, 66, BGRA(255, 255, 255, 30));        { top band }
      bmp.FillRoundRectAntialias(26, 78, 90, 86, 3, 3, Shade(ABody, 0.45));   { media slot }
      bmp.FillEllipseAntialias(100, 82, 5, 5, BGRA(120, 220, 140, 255));      { activity LED }
      FIcons.AddBitmap(AName, bmp);
    finally
      bmp.Free;
    end;
  end;

  { A page with a folded top-right corner -- the same shape TTyShellListView's
    generic-file glyph uses, so the two controls agree about what a file looks
    like when both are on screen. }
  procedure AddFile(const AName: string; ABody: TBGRAPixel);
  const
    L = 22; T = 8; R = 106; B = 120; Fold = 26;
  var
    bmp: TBGRABitmap;
  begin
    bmp := TBGRABitmap.Create(G, G, BGRAPixelTransparent);
    try
      bmp.FillPolyAntialias([PointF(L, T), PointF(R - Fold, T), PointF(R, T + Fold),
                             PointF(R, B), PointF(L, B)], ABody);
      bmp.FillPolyAntialias([PointF(R - Fold, T), PointF(R, T + Fold),
                             PointF(R - Fold, T + Fold)], Shade(ABody, 0.72));
      FIcons.AddBitmap(AName, bmp);
    finally
      bmp.Free;
    end;
  end;

begin
  FIcons := TTyImageCollection.Create(nil);
  { Order MUST match the TyShellTree*Glyph constants: folder (0), drive (1), file (2). It is the
    NAMES list below that fixes that order now, and TTyLCLImageList keeps a slot per name even
    for one that will not resolve -- so the constants cannot silently shift. }
  AddFolder('folder', BGRA(226, 176, 66));    { warm amber }
  AddDrive('drive',   BGRA(96, 116, 150));    { steel blue }
  AddFile('file',     BGRA(150, 156, 164));   { neutral grey }

  FNames := TTyVirtualImageList.Create(nil);
  FNames.Collection := FIcons;
  FNames.Names.Text := 'folder' + LineEnding + 'drive' + LineEnding + 'file';

  FImages := TTyLCLImageList.Create(nil);
  FImages.MultiResolution := False;   { a tree only ever pulls the base width }
  FImages.ImageWidth := TyShellTreeIconSize;
  FImages.Source := FNames;           { fills, in Names order }

  if FUseBuiltinIcons then
    Images := FImages;
end;

{ ---------------------------------------------------------------------------
  Node <-> path mapping
  --------------------------------------------------------------------------- }

function TTyShellTreeView.AddPathNode(AParent: PTyTreeNode; const AFullPath: string;
  AIsDir: Boolean): PTyTreeNode;
var
  idx: Integer;
begin
  Result := AddChild(AParent);
  idx := Length(FNodes);
  SetLength(FNodes, idx + 1);
  FNodes[idx].Path  := AFullPath;
  FNodes[idx].IsDir := AIsDir;
  PInteger(GetNodeData(Result))^ := idx;
  { Materialise now (headless: no paint loop to lazy-init it) so the has-children
    arrow is stamped via DoInitNode from the cheap probe. }
  InitNode(Result);
end;

function TTyShellTreeView.NodePath(Node: PTyTreeNode): string;
var
  p: Pointer;
  idx: Integer;
begin
  Result := '';
  if Node = nil then Exit;
  p := GetNodeData(Node);
  if p = nil then Exit;
  idx := PInteger(p)^;
  if (idx >= 0) and (idx <= High(FNodes)) then
    Result := FNodes[idx].Path;
end;

function TTyShellTreeView.NodeIsDir(Node: PTyTreeNode): Boolean;
var
  p: Pointer;
  idx: Integer;
begin
  Result := False;
  if Node = nil then Exit;
  p := GetNodeData(Node);
  if p = nil then Exit;
  idx := PInteger(p)^;
  if (idx >= 0) and (idx <= High(FNodes)) then
    Result := FNodes[idx].IsDir;
end;

function TTyShellTreeView.GetPathFromNode(ANode: PTyTreeNode): string;
begin
  Result := NodePath(ANode);
  if (Result <> '') and NodeIsDir(ANode) then
    Result := AppendPathDelim(Result);
end;

function TTyShellTreeView.SupportsItemModel: Boolean;
begin
  Result := False;
end;

function TTyShellTreeView.FindNode(const APath: string): PTyTreeNode;
var
  n: PTyTreeNode;
  want: string;
begin
  Result := nil;
  want := ExcludeTrailingPathDelimiter(APath);
  if want = '' then Exit;
  { A structural walk: GetNext descends into collapsed children too, so this sees
    every MATERIALISED node without expanding (or reading) anything. }
  n := GetFirst;
  while n <> nil do
  begin
    if SameFileName(ExcludeTrailingPathDelimiter(NodePath(n)), want) then
      Exit(n);
    n := GetNext(n);
  end;
end;

{ ---------------------------------------------------------------------------
  Directory intake
  --------------------------------------------------------------------------- }

function TTyShellTreeView.ReadEntries(const APath: string): TTyFsEntryArray;
var
  i, n: Integer;
  keep: TTyFsEntryArray;
  can: Boolean;
begin
  Result := TyFsReadDirectory(APath, TyShellTreeMask, FObjectTypes);

  { Per-entry veto. The common case (no handler) costs nothing. }
  if Assigned(FOnAddItem) then
  begin
    SetLength(keep, Length(Result));
    n := 0;
    for i := 0 to High(Result) do
    begin
      can := True;
      FOnAddItem(Self, APath, Result[i], can);
      if can then
      begin
        keep[n] := Result[i];
        Inc(n);
      end;
    end;
    SetLength(keep, n);
    Result := keep;
  end;

  { Ordering. TyFsSortEntries has been in the model unit all along; the tree simply
    never called it, so children arrived in raw FindFirst order with no way to ask
    for anything else. Both sorts are STABLE, so equal keys keep enumeration order. }
  case FFileSortType of
    fstAlphabet:     TyFsSortEntries(Result, fskName, True, False);
    fstFoldersFirst: TyFsSortEntries(Result, fskName, True, True);
    fstCustom:       TyFsSortEntriesBy(Result, FOnSortCompare);
  end;
end;

procedure TTyShellTreeView.PopulateChildren(Node: PTyTreeNode);
var
  entries: TTyFsEntryArray;
  i: Integer;
begin
  entries := ReadEntries(NodePath(Node));
  for i := 0 to High(entries) do
    AddPathNode(Node, entries[i].FullPath, entries[i].IsDir);
end;

class function TTyShellTreeView.GetFilesInDir(const ABaseDir, AMask: string;
  AObjectTypes: TTyFsObjectTypes; AFileSortType: TTyFsFileSortType;
  ACaseSensitivity: TTyMaskCaseSensitivity): TTyFsEntryArray;
begin
  Result := TyFsReadDirectory(ABaseDir, AMask, AObjectTypes,
                              TyFsMaskCaseSensitive(ACaseSensitivity));
  case AFileSortType of
    fstAlphabet:     TyFsSortEntries(Result, fskName, True, False);
    fstFoldersFirst: TyFsSortEntries(Result, fskName, True, True);
    { fstCustom has no comparator to defer to from a CLASS method -- there is no
      instance to read OnSortCompare from -- so it means the same as fstNone here,
      which is also what LCL's GetFilesInDirectory does with it. }
  end;
end;

{ ---------------------------------------------------------------------------
  The base's virtuals, overridden
  --------------------------------------------------------------------------- }

procedure TTyShellTreeView.DoGetText(Node: PTyTreeNode; var AText: string);
var
  p: string;
  i: Integer;
begin
  p := NodePath(Node);
  { A root node renders its curated Display ('C:', '/', a volume/home name)
    rather than the bare path. FRoots is empty while Root scopes the tree, so a
    scoped root falls through to its own folder name, which reads better than an
    absolute path in a one-node header. }
  AText := '';
  for i := 0 to High(FRoots) do
    if SameFileName(ExcludeTrailingPathDelimiter(FRoots[i].Path), p) then
    begin
      AText := FRoots[i].Display;
      Break;
    end;
  if AText = '' then
  begin
    AText := ExtractFileName(ExcludeTrailingPathDelimiter(p));
    if AText = '' then
      AText := p;   { defensive: a rooted path that collapses to '' }
  end;
  { inherited unconditionally. The root branch used to Exit here, so on exactly the nodes
    a shell tree shows FIRST -- the drives and places -- an application's OnGetText was
    never reached. Half a fix reads worse than none: the event works on some rows and not
    others, which is harder to diagnose than not working at all. }
  inherited DoGetText(Node, AText);
end;

procedure TTyShellTreeView.DoInitNode(AParent, Node: PTyTreeNode;
  var AStates: TTyNodeInitStates);
begin
  { Show an expand arrow iff this directory holds at least one entry the current
    ObjectTypes would keep. The probe stops at the first hit -- it never enumerates
    the children (that waits for the first expand). A FILE leaf is never probed:
    it has nothing below it and a disk touch per file node would be pure waste. }
  if NodeIsDir(Node) and TyFsHasEntry(NodePath(Node), FObjectTypes) then
    Include(AStates, ivsHasChildren);
  { inherited LAST so an application handler sees -- and may change -- what the shell
    decided, rather than being overwritten by it. }
  inherited DoInitNode(AParent, Node, AStates);
end;

procedure TTyShellTreeView.DoExpanding(Node: PTyTreeNode; var AAllowed: Boolean);
var
  keptFocus: string;
  refound: PTyTreeNode;
begin
  AAllowed := True;
  if NodeIsDir(Node) then
  begin
    keptFocus := '';
    { ecmRefreshedExpanding (the default, and LCL's): throw the cached child list
      away so this expand reads the directory as it is NOW. The control used to be
      hard-wired to the other branch, which meant a directory was enumerated
      exactly once per control lifetime -- anything created or deleted afterwards
      never appeared, and there was no refresh short of rebuilding the tree. }
    if (FExpandMode = ecmRefreshedExpanding) and (Node^.ChildCount > 0) then
    begin
      { The nodes about to be freed may include the focused one (collapse a folder
        while standing inside it, then re-expand). DeleteNode nulls FocusedNode, but
        nothing re-derives FSelectedPath -- so without this the tree would keep
        REPORTING a directory it is no longer standing on. }
      keptFocus := FSelectedPath;
      ResetBranch(Node);
    end;
    { Lazy population. AddChild bumps ChildCount, so the base's InitChildren
      no-ops (its ChildCount>0 guard). }
    if Node^.ChildCount = 0 then
      PopulateChildren(Node);

    if (keptFocus <> '') and (FocusedNode = nil) then
    begin
      { Only the immediate children came back, so a focus that sat deeper is gone
        for good. Re-focus what we can; otherwise say the selection is empty rather
        than keep naming a freed node's path. }
      refound := FindNode(keptFocus);
      if refound <> nil then
        FocusedNode := refound
      else
      begin
        FSelectedPath := '';
        if Assigned(FOnPathChange) then
          FOnPathChange(Self);
      end;
    end;
  end;
  inherited DoExpanding(Node, AAllowed);   { an app handler may still veto }
end;

procedure TTyShellTreeView.DoGetImageIndex(Node: PTyTreeNode; AKind: TTyVTImageKind;
  AColumn: Integer; var AGhosted: Boolean; var AIndex: Integer);
begin
  { A file leaf gets the page glyph; a top-level node of an UNSCOPED tree is one of
    the TyFsRoots places and gets the drive glyph; everything else is a folder.
    (Kind is ignored: the same glyph serves normal/selected.) }
  if not NodeIsDir(Node) then
    AIndex := TyShellTreeFileGlyph
  else if (Node <> nil) and (Node^.Parent = RootNode) and (FRoot = '') then
    AIndex := TyShellTreeDriveGlyph
  else
    AIndex := TyShellTreeFolderGlyph;
  inherited DoGetImageIndex(Node, AKind, AColumn, AGhosted, AIndex);
end;

procedure TTyShellTreeView.DoTreeChange(Node: PTyTreeNode);
begin
  { Fires on every focus/selection move (mouse, keyboard, or a programmatic
    FocusedNode from SelectPath). Cache the path + notify. }
  FSelectedPath := NodePath(Node);
  if Assigned(FOnPathChange) then
    FOnPathChange(Self);
  { ...and the designer-wired companion list, which needs no glue at all. }
  PushToList;
  inherited DoTreeChange(Node);            { OnChange belongs to the app now }
end;

{ ---------------------------------------------------------------------------
  The design-time link to a companion TTyShellListView
  --------------------------------------------------------------------------- }

procedure TTyShellTreeView.SetShellListView(AValue: TTyShellListView);
begin
  if FShellListView = AValue then Exit;
  FShellListView := AValue;
  { So Notification fires even when the partner has a different owner. }
  if AValue <> nil then
  begin
    AValue.FreeNotification(Self);
    { Adopt the current selection immediately, so wiring the pair up in the
      designer does not leave the list showing nothing until the first click. }
    PushToList;
  end;
end;

procedure TTyShellTreeView.PushToList;
begin
  if (FShellListView = nil) or (FLinkLock > 0) then Exit;
  if FSelectedPath = '' then Exit;
  if ComponentState * [csLoading, csDesigning] <> [] then Exit;
  Inc(FLinkLock);
  try
    FShellListView.Directory := FSelectedPath;
  finally
    Dec(FLinkLock);
  end;
end;

procedure TTyShellTreeView.ShellLinkSelect(const APath: string);
begin
  { Driven BY the list. The lock is held for the whole walk so the change this
    provokes cannot push straight back and start the cascade over. }
  Inc(FLinkLock);
  try
    SelectPath(APath);
  finally
    Dec(FLinkLock);
  end;
end;

procedure TTyShellTreeView.ShellLinkUpdate(const AStartDir: string);
begin
  Inc(FLinkLock);
  try
    UpdateView(AStartDir);
  finally
    Dec(FLinkLock);
  end;
end;

procedure TTyShellTreeView.Notification(AComponent: TComponent;
  Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FShellListView) then
    FShellListView := nil;
end;

{ ---------------------------------------------------------------------------
  Public API
  --------------------------------------------------------------------------- }

class function TTyShellTreeView.GetBasePath: string;
begin
  {$IFDEF MSWINDOWS}
  { On Windows there is no single base: the places ARE the drive letters, which is
    why LCL returns '' here too (shellctrls.pas:966). }
  Result := '';
  {$ELSE}
  Result := '/';
  {$ENDIF}
end;

function TTyShellTreeView.GetRootPath: string;
begin
  if FRoot <> '' then
    Result := FRoot
  else
    Result := GetBasePath;
  if Result <> '' then
    Result := AppendPathDelim(Result);
end;

procedure TTyShellTreeView.PopulateRoots;
var
  i: Integer;
begin
  Clear;
  SetLength(FNodes, 0);
  if FRoot = '' then
  begin
    FRoots := TyFsRoots;
    for i := 0 to High(FRoots) do
      AddPathNode(nil, FRoots[i].Path, True);
  end
  else
  begin
    { A scoped tree has exactly one top-level node and no curated places above it. }
    SetLength(FRoots, 0);
    AddPathNode(nil, FRoot, True);
  end;
end;

function TTyShellTreeView.SelectedPath: string;
begin
  Result := FSelectedPath;
end;

function TTyShellTreeView.GetPath: string;
begin
  Result := GetPathFromNode(FocusedNode);
end;

function TTyShellTreeView.ResolveRelative(const AValue: string): string;
var
  base: string;
begin
  Result := Trim(AValue);
  if Result = '' then Exit;
  if FilenameIsAbsolute(Result) then Exit;
  { LCL resolves a relative Path against GetRootPath (shellctrls.pas:1536-1545).
    Ours used to match absolute root-prefixed paths only, so a relative write
    silently did nothing at all. }
  base := GetRootPath;
  if base = '' then Exit;                 { no base to resolve against -- as typed }
  Result := ExpandFileNameUTF8(base + Result);
end;

procedure TTyShellTreeView.SetPath(const AValue: string);
begin
  SetDirectory(ResolveRelative(AValue));
end;

function TTyShellTreeView.SelectPath(const APath: string): Boolean;

  { True when ABase is ADir itself or a parent directory of it (case-insensitive,
    component-aware so 'C:\Us' is not a prefix of 'C:\Users'). }
  function IsSelfOrAncestor(const ABase, ADir: string): Boolean;
  begin
    Result := SameFileName(ABase, ADir) or
      ((Length(ADir) > Length(ABase)) and
       SameFileName(Copy(ADir, 1, Length(ABase)), ABase) and
       (ADir[Length(ABase) + 1] = PathDelim));
  end;

var
  target, cur: string;
  node, child, match: PTyTreeNode;
begin
  Result := False;
  FLastPathError := speEmptyPath;
  target := ExcludeTrailingPathDelimiter(Trim(APath));
  if target = '' then Exit;

  { Separate "there is no such directory" from "there is, but this tree cannot
    walk to it" BEFORE touching the tree. They need different fixes -- one is a
    typo, the other is a ShowHidden/permissions problem -- and reporting a single
    undifferentiated failure for both is barely better than the old silence. }
  { AppendPathDelim, not the bare target: ExcludeTrailingPathDelimiter turns a
    Windows drive root 'C:\' into 'C:', which names the process's CURRENT
    directory on that drive rather than its root, and probing that would reject a
    perfectly good drive. }
  if not DirectoryExistsUTF8(AppendPathDelim(target)) then
  begin
    { A tree that also shows files can legitimately be asked to select one. }
    if not ((fotFiles in FObjectTypes) and FileExistsUTF8(target)) then
    begin
      FLastPathError := speNoSuchPath;
      Exit;
    end;
  end;

  Inc(FBusy);   { we are about to hold node pointers across expands }
  try
    { Find the root node that contains the target. }
    match := nil;
    node := GetFirst;
    while node <> nil do
    begin
      if IsSelfOrAncestor(ExcludeTrailingPathDelimiter(NodePath(node)), target) then
      begin
        match := node;
        Break;
      end;
      node := GetNextSibling(node);
    end;
    if match = nil then
    begin
      FLastPathError := speNoRoot;
      Exit;
    end;

    { Descend segment by segment: expand (lazily populates children) then pick the
      child that still contains the target. Stop at the target or deepest reachable. }
    node := match;
    while not SameFileName(ExcludeTrailingPathDelimiter(NodePath(node)), target) do
    begin
      Expanded[node] := True;
      match := nil;
      child := GetFirstChild(node);
      while child <> nil do
      begin
        cur := ExcludeTrailingPathDelimiter(NodePath(child));
        if IsSelfOrAncestor(cur, target) then
        begin
          match := child;
          Break;
        end;
        child := GetNextSibling(child);
      end;
      if match = nil then Break;   { a segment is missing (permissions / case) }
      node := match;
    end;

    FocusedNode := node;    { fires the change -> DoTreeChange caches path + OnPathChange }
    ScrollIntoView(node);   { FocusedNode does not scroll on its own }

    { Landing on an ancestor is still a FAILURE to select what was asked for --
      the focus moved, so the caller is not left nowhere, but Directory would
      read back something other than what was written. Say so. }
    if SameFileName(ExcludeTrailingPathDelimiter(NodePath(node)), target) then
    begin
      FLastPathError := speNone;
      Result := True;
    end
    else
      FLastPathError := speUnreachable;
  finally
    Dec(FBusy);
    DrainPendingRefresh;
  end;
end;

procedure TTyShellTreeView.ResetBranch(ANode: PTyTreeNode);
begin
  if ANode = nil then Exit;
  if ANode^.ChildCount = 0 then Exit;   { never enumerated -- nothing cached }
  Expanded[ANode] := False;
  SetChildCount(ANode, 0);
  { SetChildCount(_, 0) also clears nsHasChildren, and SetExpanded bails on a
    node that does not carry it -- so re-stamp the arrow from the same cheap
    probe DoInitNode uses, or a later expand silently does nothing at all and
    every previously-expanded node comes back collapsed and empty. }
  if NodeIsDir(ANode) and TyFsHasEntry(NodePath(ANode), FObjectTypes) then
    Include(ANode^.States, nsHasChildren)
  else
    Exclude(ANode^.States, nsHasChildren);
end;

procedure TTyShellTreeView.CompactNodes;
var
  kept: array of TTyShellNodeInfo;
  n, idx: Integer;
  r: PTyTreeNode;
begin
  SetLength(kept, 0);
  n := 0;
  { A full pre-order walk: after a SCOPED refresh the survivors are not just the
    roots, so compaction has to see the whole structure. GetNext descends into
    collapsed children too. }
  r := GetFirst;
  while r <> nil do
  begin
    idx := PInteger(GetNodeData(r))^;
    SetLength(kept, n + 1);
    if (idx >= 0) and (idx <= High(FNodes)) then
      kept[n] := FNodes[idx]            { read the OLD row before overwriting the index }
    else
    begin
      kept[n].Path  := '';
      kept[n].IsDir := False;
    end;
    PInteger(GetNodeData(r))^ := n;
    Inc(n);
    r := GetNext(r);
  end;
  FNodes := kept;
end;

procedure TTyShellTreeView.UpdateView(const AStartDir: string = '');
var
  keep: array of string;   { paths of the nodes that were expanded, pre-order }
  focus: string;
  scope, node: PTyTreeNode;

  { Collect the expanded paths of ANode and its siblings' subtrees. Expansion is
    remembered as a PATH, not a pointer: every one of those pointers is about to
    be freed. }
  procedure Remember(ANode: PTyTreeNode; AWithSiblings: Boolean);
  var
    n: Integer;
  begin
    while ANode <> nil do
    begin
      if nsExpanded in ANode^.States then
      begin
        n := Length(keep);
        SetLength(keep, n + 1);
        keep[n] := ExcludeTrailingPathDelimiter(NodePath(ANode));
        Remember(GetFirstChild(ANode), True);
      end;
      if not AWithSiblings then Break;
      ANode := GetNextSibling(ANode);
    end;
  end;

  function WasExpanded(const APath: string): Boolean;
  var
    i: Integer;
  begin
    for i := 0 to High(keep) do
      if SameFileName(keep[i], APath) then Exit(True);
    Result := False;
  end;

  { Re-expand what was expanded. Each expand runs the normal lazy path, so the
    children come back enumerated with the CURRENT settings. }
  procedure ReExpand(ANode: PTyTreeNode; AWithSiblings: Boolean);
  begin
    while ANode <> nil do
    begin
      if WasExpanded(ExcludeTrailingPathDelimiter(NodePath(ANode))) then
      begin
        Expanded[ANode] := True;
        ReExpand(GetFirstChild(ANode), True);
      end;
      if not AWithSiblings then Break;
      ANode := GetNextSibling(ANode);
    end;
  end;

begin
  if FBusy > 0 then
  begin
    { A walk is holding node pointers. Refreshing now would free them under it.
      The scope is deliberately NOT remembered: a queued refresh is a request to
      bring the view up to date, and widening it is always safe. }
    FPendingRefresh := True;
    Exit;
  end;

  scope := nil;
  if AStartDir <> '' then
  begin
    scope := FindNode(AStartDir);
    { Nothing of that path is materialised, so there is nothing on screen to bring
      up to date. Refreshing the whole tree instead would silently do far more than
      was asked. }
    if scope = nil then Exit;
  end;

  Inc(FBusy);
  try
    focus := FSelectedPath;
    SetLength(keep, 0);
    if scope <> nil then
      Remember(scope, False)
    else
      Remember(GetFirst, True);

    if scope <> nil then
      ResetBranch(scope)
    else
    begin
      node := GetFirst;
      while node <> nil do
      begin
        ResetBranch(node);
        node := GetNextSibling(node);
      end;
    end;
    CompactNodes;

    if scope <> nil then
      ReExpand(scope, False)
    else
      ReExpand(GetFirst, True);

    { Restore the focus by path. DeleteNode already nulled FFocusedNode when it
      freed the old node, but it does it by assigning the FIELD -- no change
      notification, so FSelectedPath still holds the pre-refresh string. }
    if focus <> '' then
      SelectPath(focus);
    if (FocusedNode = nil) and (FSelectedPath <> '') then
    begin
      { The old directory is gone from disk entirely. Do not keep reporting it:
        SelectedPath must never name a directory the tree is not standing on. }
      FSelectedPath := '';
      if Assigned(FOnPathChange) then
        FOnPathChange(Self);
    end;
  finally
    Dec(FBusy);
    DrainPendingRefresh;
  end;
end;

procedure TTyShellTreeView.Refresh(ANode: PTyTreeNode);
var
  wasExpanded: Boolean;
begin
  if ANode = nil then
  begin
    { LCL's Refresh(nil) re-initialises the entire tree (shellctrls.pas:1236-1240),
      expansion included -- so does ours. UpdateView is the one that preserves it. }
    PopulateRoots;
    Exit;
  end;
  if FBusy > 0 then
  begin
    { Same hazard as UpdateView: a walk is standing on the nodes this would free. }
    FPendingRefresh := True;
    Exit;
  end;

  Inc(FBusy);
  try
    wasExpanded := nsExpanded in ANode^.States;
    ResetBranch(ANode);
    CompactNodes;
    if wasExpanded then
      Expanded[ANode] := True;   { the normal lazy path -> children come back fresh }
  finally
    Dec(FBusy);
    DrainPendingRefresh;
  end;
end;

procedure TTyShellTreeView.DrainPendingRefresh;
begin
  if (FBusy > 0) or FDraining then Exit;   { an outer walk still owns the tree }
  if not FPendingRefresh then Exit;
  FDraining := True;
  try
    FPendingRefresh := False;
    UpdateView;
  finally
    { FDraining bounds this to ONE deferred refresh per walk. A handler that
      re-requests a refresh from inside the refresh it caused would otherwise
      recurse without end; the re-request stays queued for the next walk. }
    FDraining := False;
  end;
end;

{ ---------------------------------------------------------------------------
  Setters
  --------------------------------------------------------------------------- }

procedure TTyShellTreeView.SetRoot(const AValue: string);
var
  wanted: string;
begin
  if FRoot = AValue then Exit;
  wanted := Trim(AValue);
  if wanted <> '' then
  begin
    wanted := ExcludeTrailingPathDelimiter(ExpandFileNameUTF8(wanted));
    if not DirectoryExistsUTF8(AppendPathDelim(wanted)) then
    begin
      FLastPathError := speNoSuchPath;
      { Streaming a stale .lfm Root, or typing one into the object inspector, must
        not break form loading or take the IDE down -- the same carve-out LCL makes
        at shellctrls.pas:621-624. }
      if ([csLoading, csDesigning] * ComponentState) <> [] then Exit;
      raise ETyShellInvalidPath.CreateFmt(TyShellInvalidRootMsg, [AValue]);
    end;
  end;
  FRoot := wanted;
  FSelectedPath := '';   { the node it named is about to be freed }
  PopulateRoots;
end;

procedure TTyShellTreeView.SetObjectTypes(AValue: TTyFsObjectTypes);
begin
  if FObjectTypes = AValue then Exit;
  FObjectTypes := AValue;
  { ShowHidden is a VIEW of the fotHidden bit, not a second copy of it: writing the
    set has to move it too, or the two properties disagree about the same state and
    a 'Show hidden' checkbox bound to ShowHidden reads back a lie. }
  FShowHidden := fotHidden in FObjectTypes;
  UpdateView;
end;

procedure TTyShellTreeView.SetShowHidden(AValue: Boolean);
begin
  if FShowHidden = AValue then Exit;
  FShowHidden := AValue;
  if AValue then
    Include(FObjectTypes, fotHidden)
  else
    Exclude(FObjectTypes, fotHidden);
  { Refresh NOW. This used to set the flag and stop, on the grounds that a
    property write must not free node handles a consumer is holding, and that on
    a host whose current directory sits under a hidden ancestor a rebuild would
    strand that path. Both hazards are real and both are handled rather than
    avoided: UpdateView defers itself while a walk is in progress (FBusy), and it
    restores the focus by path, degrading to the deepest still-reachable ancestor
    instead of stranding it. What is NOT defensible is the visible result of
    doing nothing -- the setting appeared broken until some unrelated re-expand
    happened to apply it, and TTyShellListView.ShowHidden, the sibling control in
    the same family, has always re-read on the write. }
  UpdateView;
end;

procedure TTyShellTreeView.SetFileSortType(AValue: TTyFsFileSortType);
begin
  if FFileSortType = AValue then Exit;
  FFileSortType := AValue;
  UpdateView;
end;

procedure TTyShellTreeView.SetOnSortCompare(AValue: TTyFsCompareEvent);
begin
  { Field-by-field: FPC has no '=' for TMethod, and in objfpc mode comparing two
    `function ... of object` values directly would try to CALL them. }
  if (TMethod(FOnSortCompare).Code = TMethod(AValue).Code) and
     (TMethod(FOnSortCompare).Data = TMethod(AValue).Data) then Exit;
  FOnSortCompare := AValue;
  { Assigning a comparator IS the request to use it, so switch to fstCustom --
    exactly what LCL's SetOnSortCompare does (shellctrls.pas:693-700). Clearing it
    drops back to unordered rather than leaving fstCustom with nothing to call. }
  if Assigned(AValue) then
    FFileSortType := fstCustom
  else if FFileSortType = fstCustom then
    FFileSortType := fstNone;
  UpdateView;
end;

procedure TTyShellTreeView.SetUseBuiltinIcons(AValue: Boolean);
begin
  if FUseBuiltinIcons = AValue then Exit;
  FUseBuiltinIcons := AValue;
  if AValue then
    Images := FImages
  else
    { Detach rather than free: the switch is a toggle, and FImages/FIcons stay
      owned by this control either way (the destructor frees them). }
    Images := nil;
  Invalidate;
end;

procedure TTyShellTreeView.SetDirectory(const AValue: string);
begin
  if SelectPath(AValue) then Exit;
  { '' is not a failed selection, it is an absent one. }
  if FLastPathError in [speNone, speEmptyPath] then Exit;
  { Streaming a stale .lfm path, or typing one into the object inspector, must
    not break form loading or take the IDE down -- the same carve-out LCL makes
    at shellctrls.pas:621. LastPathError still records what happened, so a
    designer-time caller is not blind either. }
  if ([csLoading, csDesigning] * ComponentState) <> [] then Exit;
  raise ETyShellInvalidPath.CreateFmt(TyShellInvalidPathMsg,
    [AValue, GetEnumName(TypeInfo(TTyShellPathError), Ord(FLastPathError))]);
end;

initialization
  { So a .lfm that streams a TTyShellTreeView resolves the class. }
  RegisterClass(TTyShellTreeView);

end.
