unit test.parity.shell;
{ API-parity guards for the shell family: TTyShellListView, TTyShellTreeView and
  TTyFilterComboBox, measured against C:/lazarus/lcl/shellctrls.pas and
  C:/lazarus/lcl/filectrl.pp. Each group names the LCL declaration it is measured
  against, so a reader can check the claim rather than trust it.

  FIXTURE LOCATION: the list fixture lives under GetTempDir (the list reads one
  directory directly, so a hidden ancestor is irrelevant). The TREE fixtures live
  under GetUserDir, because on Windows GetTempDir sits under ...\AppData\... which
  carries FILE_ATTRIBUTE_HIDDEN -- a tree walking down from a drive root with
  ShowHidden=False can never reach it. Same reasoning, and the same asserted
  precondition, as test.parity.shelldivider. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, LazFileUtils, FileUtil, fpcunit, testregistry,
  tyControls.Columns, tyControls.FileSystem, tyControls.TreeView,
  tyControls.ShellListView, tyControls.ShellTreeView, tyControls.FilterComboBox;

type
  TShellListProbe = class(TTyShellListView)
  public
    procedure XCommitEdit(AIndex: Integer; const AText: string);
    function  XGetItemText(AIndex, AColumn: Integer): string;
    function  XGetItemCount: Integer;
    function  XGetItemImageIndex(AIndex, AColumn: Integer): Integer;
    procedure XResize;
  end;

  TShellListParityTest = class(TTestCase)
  private
    FRoot: string;
    FLV:   TShellListProbe;
    FAddItemSeen:    Integer;
    FAddItemVeto:    string;
    FAddItemBadBase: Boolean;
    procedure WriteBytes(const AFullName: string; ACount: Integer);
    procedure HandleAddItem(Sender: TObject; const ABasePath: string;
      const AEntry: TTyFsEntry; var ACanAdd: Boolean);
    function  RowOfName(const AName: string): Integer;
    function  HasName(const AName: string): Boolean;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure CommitEditReReadsWithoutAnExplicitUpdateView;
    procedure UpdateViewKeepsTheSelectedFileNotTheRowNumber;
    procedure UpdateViewRestoresTheSelectedSetByPathNotByRow;
    procedure UpdateViewDropsAGoneFileFromTheSelection;
    procedure RootIsTheListedDirectoryUnderLclsName;
    procedure ObjectTypesSelectsFoldersOnlyAndFilesOnly;
    procedure ObjectTypesAndShowHiddenStayInSync;
    procedure MaskCaseSensitivityMakesTheMaskExactWhenAsked;
    procedure MaskCaseSensitivityDefaultsToInsensitive;
    procedure OnAddItemCanVetoASingleEntry;
    procedure OnAddItemIsHandedTheBasePathAndTheEntry;
    procedure AutoSizeColumnsFillsTheClientWidth;
    procedure AutoSizeColumnsOffLeavesTheWidthsAlone;
    procedure UseBuiltInIconsOffSuppressesTheKindGlyph;
  end;

  { ===================================================================
    TTyShellTreeView
    =================================================================== }
  TShellTreeProbe = class(TTyShellTreeView)
  public
    function XGetFirstRoot: PTyTreeNode;
  end;

  TShellTreeParityTest = class(TTestCase)
  private
    FRoot:  string;    { <userdir>/typarityshelltree_<pid> }
    FDirA:  string;    { <root>/a, holds b }
    FTree:  TShellTreeProbe;
    FAddItemSeen: Integer;
    FAddItemVeto: string;
    procedure HandleAddItem(Sender: TObject; const ABasePath: string;
      const AEntry: TTyFsEntry; var ACanAdd: Boolean);
    function  CompareByNameDesc(const A, B: TTyFsEntry): Integer;
    function  NodeForPath(const APath: string): PTyTreeNode;
    function  ChildNames(ANode: PTyTreeNode): string;
    function  HasChildNamed(ANode: PTyTreeNode; const AName: string): Boolean;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { --- GetPathFromNode: public node -> path (shellctrls.pas:131) -------- }
    procedure GetPathFromNodeIsPublicAndDelimitsDirectories;
    { --- Root: scope the tree to one directory (shellctrls.pas:141) ------- }
    procedure RootScopesTheTreeToOneDirectory;
    procedure EmptyRootRestoresTheMachinePlaces;
    procedure InvalidRootRaisesButNotAtDesignTime;
    { --- GetRootPath / GetBasePath (shellctrls.pas:125-127) --------------- }
    procedure GetRootPathReportsTheEffectiveRoot;
    { --- GetFilesInDir (shellctrls.pas:127-129) --------------------------- }
    procedure GetFilesInDirIsAReusableStaticEnumerator;
    { --- Path: LCL's name and LCL's contract (shellctrls.pas:142) --------- }
    procedure PathReadsBackWithATrailingDelimiter;
    procedure PathAcceptsARootRelativeWrite;
    { --- ObjectTypes (shellctrls.pas:138) --------------------------------- }
    procedure ObjectTypesCanShowFilesAsLeaves;
    procedure ObjectTypesAndShowHiddenStayInSync;
    { --- FileSortType + OnSortCompare (shellctrls.pas:140/144) ------------ }
    procedure FileSortTypeOrdersChildrenAlphabetically;
    procedure FileSortTypeFoldersFirstPutsDirectoriesAhead;
    procedure OnSortCompareTakesOverTheOrdering;
    { --- OnAddItem (shellctrls.pas:143) ----------------------------------- }
    procedure OnAddItemCanVetoAFolder;
    { --- Refresh(ANode) (shellctrls.pas:133) ------------------------------ }
    procedure RefreshNodeReReadsOnlyThatBranch;
    { --- UpdateView(AStartDir) (shellctrls.pas:134) ----------------------- }
    procedure UpdateViewStartDirLimitsTheRefreshToOneSubtree;
    { --- ExpandCollapseMode (shellctrls.pas:118) -------------------------- }
    procedure ExpandCollapseModeRefreshedExpandingReReadsOnEachExpand;
    procedure ExpandCollapseModeKeepChildrenIsTheOldBehaviour;
    { --- UseBuiltinIcons (shellctrls.pas:135) ----------------------------- }
    procedure UseBuiltinIconsOffDetachesTheBuiltInList;
  end;

  { ===================================================================
    The design-time links + TTyFilterComboBox
    =================================================================== }
  TShellLinkParityTest = class(TTestCase)
  private
    FRoot:  string;
    FDirA:  string;
    FTree:  TTyShellTreeView;
    FList:  TTyShellListView;
    FCombo: TTyFilterComboBox;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { --- TTyShellTreeView.ShellListView (shellctrls.pas:139) -------------- }
    procedure TreeSelectionDrivesTheLinkedList;
    procedure TreeUnlinksTheListWhenItIsFreed;
    { --- TTyShellListView.ShellTreeView (shellctrls.pas:301) -------------- }
    procedure ListNavigationDrivesTheLinkedTree;
    procedure ListUnlinksTheTreeWhenItIsFreed;
    procedure TwoWayLinkSettlesInsteadOfRecursing;
    { --- TTyFilterComboBox.ShellListView (filectrl.pp:167) ---------------- }
    procedure FilterComboPushesItsMaskIntoTheLinkedList;
    procedure FilterComboUnlinksTheListWhenItIsFreed;
    { --- ConvertFilterToStrings (filectrl.pp:163) ------------------------- }
    procedure ConvertFilterToStringsFillsACallerSuppliedList;
    procedure ConvertFilterToStringsAppendsWhenAskedNotToClear;
  end;

implementation

function SamePath(const A, B: string): Boolean;
begin
  Result := SameFileName(ExcludeTrailingPathDelimiter(A),
                         ExcludeTrailingPathDelimiter(B));
end;

function BaseNameOf(const APath: string): string;
begin
  Result := ExtractFileName(ExcludeTrailingPathDelimiter(APath));
end;

procedure TShellListProbe.XCommitEdit(AIndex: Integer; const AText: string);
begin
  CommitEdit(AIndex, AText);
end;

function TShellListProbe.XGetItemText(AIndex, AColumn: Integer): string;
begin
  Result := GetItemText(AIndex, AColumn);
end;

function TShellListProbe.XGetItemCount: Integer;
begin
  Result := GetItemCount;
end;

function TShellListProbe.XGetItemImageIndex(AIndex, AColumn: Integer): Integer;
begin
  Result := GetItemImageIndex(AIndex, AColumn);
end;

procedure TShellListProbe.XResize;
begin
  Resize;
end;

procedure TShellListParityTest.WriteBytes(const AFullName: string; ACount: Integer);
var
  fs: TFileStream;
  buf: TBytes;
begin
  SetLength(buf, ACount);
  if ACount > 0 then FillChar(buf[0], ACount, Byte('x'));
  fs := TFileStream.Create(AFullName, fmCreate);
  try
    if ACount > 0 then fs.WriteBuffer(buf[0], ACount);
  finally
    fs.Free;
  end;
end;

procedure TShellListParityTest.SetUp;
var
  hidden: string;
begin
  FAddItemSeen := 0;
  FAddItemVeto := '';
  FAddItemBadBase := False;

  FRoot := ChompPathDelim(AppendPathDelim(GetTempDir) +
                          'typarityshelllist_' + IntToStr(GetProcessID));
  if DirectoryExistsUTF8(FRoot) then DeleteDirectory(FRoot, False);
  ForceDirectoriesUTF8(FRoot);
  ForceDirectoriesUTF8(AppendPathDelim(FRoot) + 'dir_a');
  ForceDirectoriesUTF8(AppendPathDelim(FRoot) + 'dir_b');
  WriteBytes(AppendPathDelim(FRoot) + 'm.txt', 10);
  WriteBytes(AppendPathDelim(FRoot) + 'n.txt', 20);
  WriteBytes(AppendPathDelim(FRoot) + 'p.LOG', 30);   { upper-case extension }
  WriteBytes(AppendPathDelim(FRoot) + 'q.log', 40);   { lower-case extension }

  hidden := AppendPathDelim(FRoot) + '.hiddenfile';
  WriteBytes(hidden, 3);
  {$IFDEF MSWINDOWS}
  FileSetAttrUTF8(hidden, faHidden);
  {$ENDIF}

  FLV := TShellListProbe.Create(nil);
end;

procedure TShellListParityTest.TearDown;
begin
  FreeAndNil(FLV);
  if (FRoot <> '') and DirectoryExistsUTF8(FRoot) then DeleteDirectory(FRoot, False);
end;

procedure TShellListParityTest.HandleAddItem(Sender: TObject;
  const ABasePath: string; const AEntry: TTyFsEntry; var ACanAdd: Boolean);
begin
  Inc(FAddItemSeen);
  if not SamePath(ABasePath, FRoot) then
    FAddItemBadBase := True;
  if (FAddItemVeto <> '') and SameFileName(AEntry.Name, FAddItemVeto) then
    ACanAdd := False;
end;

function TShellListParityTest.RowOfName(const AName: string): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to FLV.XGetItemCount - 1 do
    if SameFileName(FLV.XGetItemText(i, 0), AName) then Exit(i);
end;

function TShellListParityTest.HasName(const AName: string): Boolean;
begin
  Result := RowOfName(AName) >= 0;
end;

{ Renaming Refresh -> UpdateView left CommitEdit still calling Refresh, which now
  binds to TControl.Refresh (repaint). So an F2 rename changed the file on disk and
  the row kept showing the OLD name. The existing rename test could not see it: it
  called UpdateView itself. }
procedure TShellListParityTest.CommitEditReReadsWithoutAnExplicitUpdateView;
var
  i: Integer;
begin
  FLV.Directory := FRoot;
  i := RowOfName('m.txt');
  AssertTrue('precondition: m.txt is listed', i >= 0);
  { The ONLY call. Nothing re-reads the directory afterwards. }
  FLV.XCommitEdit(i, 'renamed.txt');
  AssertTrue('the rename really landed on disk',
    FileExistsUTF8(AppendPathDelim(FRoot) + 'renamed.txt'));
  AssertTrue('the view shows the new name with no further call', HasName('renamed.txt'));
  AssertTrue('...and no longer shows the old one', not HasName('m.txt'));
end;

{ LCL saves Selected.Caption and restores it with FindCaption after repopulating
  (shellctrls.pas:1990-2011). Ours re-read and left the selection pinned to the row
  INDEX, so a file created above the selected row moved the highlight onto a
  different file -- and a dialog then returns a name the user never picked. }
procedure TShellListParityTest.UpdateViewKeepsTheSelectedFileNotTheRowNumber;
var
  before: string;
begin
  FLV.Directory := FRoot;
  FLV.ItemIndex := RowOfName('m.txt');
  before := FLV.SelectedFile;
  AssertTrue('precondition: m.txt is selected', SameFileName(BaseNameOf(before), 'm.txt'));
  WriteBytes(AppendPathDelim(FRoot) + 'a_inserted.txt', 5);
  FLV.UpdateView;
  AssertTrue('the inserted file really did land above the selection',
    RowOfName('a_inserted.txt') < RowOfName('m.txt'));
  AssertEquals('the SELECTED FILE survived the refresh, not the row number',
    before, FLV.SelectedFile);
end;

{ The multi-selection half, and the one that actually pins the restore. FOCUS
  coming back empty when its file is gone is NOT evidence on its own: ClearSelection
  (ListView.pas:1901) sets FItemIndex := -1 anyway, so a UpdateView that restored
  nothing at all would still look right by that measure. The selected SET is what
  only the by-path restore can produce. }
procedure TShellListParityTest.UpdateViewRestoresTheSelectedSetByPathNotByRow;
begin
  FLV.Directory := FRoot;
  FLV.MultiSelect := True;
  { ItemIndex FIRST: its setter re-establishes a single selection, so writing it
    after the bits would collapse them back to one row. }
  FLV.ItemIndex := RowOfName('m.txt');
  FLV.Selected[RowOfName('m.txt')] := True;
  FLV.Selected[RowOfName('q.log')] := True;
  AssertEquals('precondition: two rows selected', 2, FLV.SelCount);

  { Sorts above both of them, so every later row shifts down by one: an
    index-pinned selection now names two DIFFERENT files. }
  WriteBytes(AppendPathDelim(FRoot) + 'a_inserted.txt', 5);
  FLV.UpdateView;

  AssertEquals('the same two FILES are still selected', 2, FLV.SelCount);
  AssertTrue('...m.txt by path', FLV.Selected[RowOfName('m.txt')]);
  AssertTrue('...q.log by path', FLV.Selected[RowOfName('q.log')]);
  AssertTrue('...and the row that pushed them down is not selected',
    not FLV.Selected[RowOfName('a_inserted.txt')]);
end;

procedure TShellListParityTest.UpdateViewDropsAGoneFileFromTheSelection;
begin
  FLV.Directory := FRoot;
  FLV.MultiSelect := True;
  FLV.ItemIndex := RowOfName('m.txt');   { see above: order matters }
  FLV.Selected[RowOfName('m.txt')] := True;
  FLV.Selected[RowOfName('n.txt')] := True;
  AssertEquals('precondition: two rows selected', 2, FLV.SelCount);

  DeleteFileUTF8(AppendPathDelim(FRoot) + 'm.txt');
  FLV.UpdateView;

  AssertEquals('only the file that survived is still selected', 1, FLV.SelCount);
  AssertTrue('...and it is n.txt, found by path', FLV.Selected[RowOfName('n.txt')]);
  AssertTrue('a focus whose file is gone must not slide onto a survivor',
    FLV.SelectedFile = '');
end;

{ shellctrls.pas:300 -- LCL's name for the listed directory. }
procedure TShellListParityTest.RootIsTheListedDirectoryUnderLclsName;
begin
  FLV.Root := FRoot;
  AssertTrue('Root reads back the directory it listed', SamePath(FLV.Root, FRoot));
  AssertTrue('...and Directory is the same storage', SamePath(FLV.Directory, FRoot));
  AssertTrue('...and it actually read the directory', HasName('m.txt'));
end;

{ shellctrls.pas:299. Ours fixed the set in the constructor and exposed only the
  hidden bit, so a files-only or folders-only pane could not be configured at all. }
procedure TShellListParityTest.ObjectTypesSelectsFoldersOnlyAndFilesOnly;
begin
  FLV.Directory := FRoot;
  AssertTrue('precondition: the mixed default shows both',
    HasName('dir_a') and HasName('m.txt'));

  FLV.ObjectTypes := [fotFiles];
  AssertTrue('files-only drops the folders', not HasName('dir_a'));
  AssertTrue('...and keeps the files', HasName('m.txt'));

  FLV.ObjectTypes := [fotFolders];
  AssertTrue('folders-only keeps the folders', HasName('dir_a'));
  AssertTrue('...and drops the files', not HasName('m.txt'));
end;

procedure TShellListParityTest.ObjectTypesAndShowHiddenStayInSync;
begin
  FLV.Directory := FRoot;
  AssertTrue('precondition: hidden is off', not FLV.ShowHidden);
  AssertTrue('...and the hidden bit is not in the set',
    not (fotHidden in FLV.ObjectTypes));

  FLV.ShowHidden := True;
  AssertTrue('ShowHidden:=True sets the bit', fotHidden in FLV.ObjectTypes);

  FLV.ObjectTypes := FLV.ObjectTypes - [fotHidden];
  AssertTrue('clearing the bit clears ShowHidden', not FLV.ShowHidden);

  FLV.ObjectTypes := FLV.ObjectTypes + [fotHidden];
  AssertTrue('setting the bit sets ShowHidden', FLV.ShowHidden);
  AssertTrue('...and the hidden entry is really listed', HasName('.hiddenfile'));
end;

{ shellctrls.pas:298. TyFsReadDirectory matched case-insensitively unconditionally,
  so an app that needed exact-case matching had no way to ask. }
procedure TShellListParityTest.MaskCaseSensitivityMakesTheMaskExactWhenAsked;
begin
  FLV.Directory := FRoot;
  FLV.MaskCaseSensitivity := mcsCaseSensitive;
  FLV.Mask := '*.log';
  AssertTrue('the exact-case match keeps q.log', HasName('q.log'));
  AssertTrue('...and rejects p.LOG', not HasName('p.LOG'));
end;

procedure TShellListParityTest.MaskCaseSensitivityDefaultsToInsensitive;
begin
  AssertEquals('the default is this library''s file-dialog convention',
    Ord(mcsCaseInsensitive), Ord(FLV.MaskCaseSensitivity));
  FLV.Directory := FRoot;
  FLV.Mask := '*.log';
  AssertTrue('both cases match by default', HasName('q.log') and HasName('p.LOG'));
end;

{ shellctrls.pas:303 -- per-entry veto. }
procedure TShellListParityTest.OnAddItemCanVetoASingleEntry;
begin
  FLV.OnAddItem := @HandleAddItem;
  FAddItemVeto := 'm.txt';
  FLV.Directory := FRoot;
  AssertTrue('the vetoed entry is not in the view', not HasName('m.txt'));
  AssertTrue('...and its neighbours still are', HasName('n.txt') and HasName('dir_a'));
end;

procedure TShellListParityTest.OnAddItemIsHandedTheBasePathAndTheEntry;
begin
  FLV.OnAddItem := @HandleAddItem;
  FLV.Directory := FRoot;
  AssertTrue('the handler ran once per enumerated entry', FAddItemSeen > 0);
  AssertEquals('once per surviving entry', FLV.XGetItemCount, FAddItemSeen);
  AssertTrue('and was handed the directory being read', not FAddItemBadBase);
end;

{ shellctrls.pas:296 + AdjustColWidths (1913-1945). Fixed 220/90/120/140 widths
  meant a wide pane left dead space and a narrow one clipped the last column. }
procedure TShellListParityTest.AutoSizeColumnsFillsTheClientWidth;
var
  total, i: Integer;
begin
  AssertTrue('default is on, like LCL''s', FLV.AutoSizeColumns);
  FLV.Directory := FRoot;
  FLV.SetBounds(0, 0, 700, 300);
  FLV.XResize;

  total := 0;
  for i := 0 to FLV.Header.Columns.Count - 1 do
    Inc(total, TTyColumn(FLV.Header.Columns.Items[i]).Width);
  AssertEquals('the columns fill the pane exactly', FLV.ClientWidth, total);

  FLV.SetBounds(0, 0, 320, 300);
  FLV.XResize;
  total := 0;
  for i := 0 to FLV.Header.Columns.Count - 1 do
    Inc(total, TTyColumn(FLV.Header.Columns.Items[i]).Width);
  AssertEquals('...and shrink with it instead of clipping', FLV.ClientWidth, total);
end;

procedure TShellListParityTest.AutoSizeColumnsOffLeavesTheWidthsAlone;
var
  w0: Integer;
begin
  FLV.AutoSizeColumns := False;
  FLV.Directory := FRoot;
  w0 := TTyColumn(FLV.Header.Columns.Items[0]).Width;
  FLV.SetBounds(0, 0, 900, 300);
  FLV.XResize;
  AssertEquals('with the switch off the author''s widths are untouched',
    w0, TTyColumn(FLV.Header.Columns.Items[0]).Width);
end;

{ shellctrls.pas:302 -- a text-only pane has to be askable for. }
procedure TShellListParityTest.UseBuiltInIconsOffSuppressesTheKindGlyph;
var
  row: Integer;
begin
  FLV.Directory := FRoot;
  row := RowOfName('m.txt');
  AssertTrue('precondition: a row exists', row >= 0);
  AssertTrue('default is on, like LCL''s', FLV.UseBuiltInIcons);
  AssertTrue('by default the built-in kind glyph is used',
    FLV.XGetItemImageIndex(row, 0) >= 0);

  FLV.UseBuiltInIcons := False;
  AssertTrue('with the switch off no glyph index is claimed',
    FLV.XGetItemImageIndex(row, 0) < 0);
  AssertTrue('...and the built-in list is off the control', FLV.SmallImages = nil);

  FLV.UseBuiltInIcons := True;
  AssertTrue('and both come back', (FLV.XGetItemImageIndex(row, 0) >= 0)
    and (FLV.SmallImages <> nil));
end;

{ ===========================================================================
  TShellTreeProbe
  =========================================================================== }

function TShellTreeProbe.XGetFirstRoot: PTyTreeNode;
begin
  Result := GetFirst;
end;

{ ===========================================================================
  TShellTreeParityTest
  =========================================================================== }

procedure TShellTreeParityTest.SetUp;
var
  fs: TFileStream;
begin
  FAddItemSeen := 0;
  FAddItemVeto := '';

  FRoot := ChompPathDelim(AppendPathDelim(GetUserDir) +
                          'typarityshelltree_' + IntToStr(GetProcessID));
  if DirectoryExistsUTF8(FRoot) then DeleteDirectory(FRoot, False);
  ForceDirectoriesUTF8(FRoot);

  FDirA := AppendPathDelim(FRoot) + 'a';
  ForceDirectoriesUTF8(AppendPathDelim(FDirA) + 'b');
  { Three siblings whose FindFirst order is not guaranteed to be the sorted one. }
  ForceDirectoriesUTF8(AppendPathDelim(FRoot) + 'zeta');
  ForceDirectoriesUTF8(AppendPathDelim(FRoot) + 'alpha');
  fs := TFileStream.Create(AppendPathDelim(FRoot) + 'leaf.txt', fmCreate);
  fs.Free;

  FTree := TShellTreeProbe.Create(nil);

  { PRECONDITION, asserted not assumed: with ShowHidden off the fixture must be
    reachable from a seeded root, i.e. no ancestor of GetUserDir is hidden on this
    host. Without it every guard below would be meaningless rather than wrong. }
  AssertTrue('fixture reachable with ShowHidden=False (no hidden ancestor)',
    FTree.SelectPath(FRoot));
end;

procedure TShellTreeParityTest.TearDown;
begin
  FreeAndNil(FTree);
  if (FRoot <> '') and DirectoryExistsUTF8(FRoot) then DeleteDirectory(FRoot, False);
end;

procedure TShellTreeParityTest.HandleAddItem(Sender: TObject;
  const ABasePath: string; const AEntry: TTyFsEntry; var ACanAdd: Boolean);
begin
  Inc(FAddItemSeen);
  if (FAddItemVeto <> '') and SameFileName(AEntry.Name, FAddItemVeto) then
    ACanAdd := False;
end;

function TShellTreeParityTest.CompareByNameDesc(const A, B: TTyFsEntry): Integer;
begin
  Result := -CompareFilenames(A.Name, B.Name);
end;

function TShellTreeParityTest.NodeForPath(const APath: string): PTyTreeNode;
begin
  Result := nil;
  if FTree.SelectPath(APath) then
    Result := FTree.FocusedNode;
  AssertTrue('fixture node ' + APath + ' is reachable', Result <> nil);
end;

function TShellTreeParityTest.ChildNames(ANode: PTyTreeNode): string;
var
  ch: PTyTreeNode;
begin
  Result := '';
  if ANode = nil then Exit;
  ch := FTree.GetFirstChild(ANode);
  while ch <> nil do
  begin
    if Result <> '' then Result := Result + ',';
    Result := Result + BaseNameOf(FTree.GetPathFromNode(ch));
    ch := FTree.GetNextSibling(ch);
  end;
end;

function TShellTreeParityTest.HasChildNamed(ANode: PTyTreeNode;
  const AName: string): Boolean;
var
  ch: PTyTreeNode;
begin
  Result := False;
  if ANode = nil then Exit;
  ch := FTree.GetFirstChild(ANode);
  while ch <> nil do
  begin
    if SameFileName(BaseNameOf(FTree.GetPathFromNode(ch)), AName) then Exit(True);
    ch := FTree.GetNextSibling(ch);
  end;
end;

{ Ours was PROTECTED, so from outside the class only the FOCUSED path was
  reachable: no multi-select harvesting, no path from a draw handler, no drag
  source. LCL's is public and appends a delimiter for a directory. }
procedure TShellTreeParityTest.GetPathFromNodeIsPublicAndDelimitsDirectories;
var
  n, child: PTyTreeNode;
begin
  n := NodeForPath(FRoot);
  FTree.Expanded[n] := True;
  child := FTree.GetFirstChild(n);
  AssertTrue('the fixture has children', child <> nil);
  { The point of the claim: a path for a node that is NOT the focused one. }
  AssertTrue('a non-focused node resolves to its own path',
    not SamePath(FTree.GetPathFromNode(child), FTree.SelectedPath));
  AssertTrue('...which is a real child of the fixture',
    SamePath(ExtractFileDir(ExcludeTrailingPathDelimiter(
      FTree.GetPathFromNode(child))), FRoot));
  AssertEquals('a directory node is delimiter-terminated (LCL contract)',
    PathDelim, FTree.GetPathFromNode(child)[Length(FTree.GetPathFromNode(child))]);
  AssertEquals('a nil node is '''', not a crash', '', FTree.GetPathFromNode(nil));
end;

{ shellctrls.pas:141 -- you could not show a tree scoped to one folder at all;
  every instance always showed every drive. }
procedure TShellTreeParityTest.RootScopesTheTreeToOneDirectory;
var
  n: PTyTreeNode;
begin
  FTree.Root := FRoot;
  n := FTree.XGetFirstRoot;
  AssertTrue('the tree has a top-level node', n <> nil);
  AssertTrue('...and no sibling beside it', FTree.GetNextSibling(n) = nil);
  AssertTrue('...which is the requested directory',
    SamePath(FTree.GetPathFromNode(n), FRoot));

  FTree.Expanded[n] := True;
  AssertTrue('and it enumerates its own children', HasChildNamed(n, 'a'));
  AssertTrue('a path outside the scope is now unreachable',
    not FTree.SelectPath(GetUserDir));
  AssertEquals('...reported as speNoRoot, not as a missing directory',
    Ord(speNoRoot), Ord(FTree.LastPathError));
end;

procedure TShellTreeParityTest.EmptyRootRestoresTheMachinePlaces;
var
  n: PTyTreeNode;
  count: Integer;
begin
  FTree.Root := FRoot;
  FTree.Root := '';
  n := FTree.XGetFirstRoot;
  count := 0;
  while n <> nil do
  begin
    Inc(count);
    n := FTree.GetNextSibling(n);
  end;
  { Length(TyFsRoots), not just ">= 1": a rebuild that seeded only the FIRST place
    would still satisfy ">= 1" and would still reach the fixture on Windows, where
    the fixture lives under the first drive. }
  AssertEquals('an empty Root is the machine-wide places list again',
    Length(TyFsRoots), count);
  AssertTrue('and the fixture is reachable from it again', FTree.SelectPath(FRoot));
end;

procedure TShellTreeParityTest.InvalidRootRaisesButNotAtDesignTime;
var
  raised: Boolean;
begin
  raised := False;
  try
    FTree.Root := AppendPathDelim(FRoot) + 'no_such_root_xyz';
  except
    on E: ETyShellInvalidPath do raised := True;
  end;
  AssertTrue('a Root that does not exist raises (LCL: shellctrls.pas:625)', raised);
  AssertEquals('and the tree kept the root it had', '', FTree.Root);

  { ...but never at design time: a stale .lfm Root must not take the IDE down. }
  FTree.SetDesigning(True, False);
  raised := False;
  try
    FTree.Root := AppendPathDelim(FRoot) + 'no_such_root_xyz';
  except
    on E: ETyShellInvalidPath do raised := True;
  end;
  FTree.SetDesigning(False, False);
  AssertTrue('no raise at design time', not raised);
end;

procedure TShellTreeParityTest.GetRootPathReportsTheEffectiveRoot;
begin
  AssertEquals('with no Root the effective root is the machine base path',
    TTyShellTreeView.GetBasePath, FTree.GetRootPath);
  FTree.Root := FRoot;
  AssertTrue('with a Root it is that directory', SamePath(FTree.GetRootPath, FRoot));
  AssertEquals('...delimiter-terminated, like LCL''s',
    PathDelim, FTree.GetRootPath[Length(FTree.GetRootPath)]);
end;

procedure TShellTreeParityTest.GetFilesInDirIsAReusableStaticEnumerator;
var
  e: TTyFsEntryArray;
  names: string;
  i: Integer;
begin
  { A CLASS function, usable with no instance -- the point of LCL's GetFilesInDir.
    fstFoldersFirst, not fstAlphabet: the fixture's raw FindFirst order on NTFS is
    already alphabetical ('a,alpha,leaf.txt,zeta'), so an alphabetical assertion
    would pass whether the sort ran or not. Folders-first puts leaf.txt LAST, which
    no enumeration order produces by accident. }
  e := TTyShellTreeView.GetFilesInDir(FRoot, '*', [fotFolders, fotFiles],
                                      fstFoldersFirst);
  names := '';
  for i := 0 to High(e) do
  begin
    if names <> '' then names := names + ',';
    names := names + e[i].Name;
  end;
  AssertEquals('folders first, then files, each name-ordered',
    'a,alpha,zeta,leaf.txt', names);

  e := TTyShellTreeView.GetFilesInDir(FRoot, '*.txt', [fotFiles], fstAlphabet);
  AssertEquals('the mask still applies to files', 1, Length(e));
  AssertEquals('', 'leaf.txt', e[0].Name);
end;

{ shellctrls.pas:142 -- `Tree.Path := X` did not compile, and Path's trailing
  delimiter is part of the contract every LCL caller relies on. }
procedure TShellTreeParityTest.PathReadsBackWithATrailingDelimiter;
begin
  AssertTrue('precondition', FTree.SelectPath(FDirA));
  AssertEquals('Path is delimiter-terminated', AppendPathDelim(FDirA), FTree.Path);
  AssertEquals('Directory is the same selection, raw',
    ExcludeTrailingPathDelimiter(FDirA), FTree.Directory);
end;

procedure TShellTreeParityTest.PathAcceptsARootRelativeWrite;
begin
  FTree.Root := FRoot;
  { LCL's SetPath resolves a relative value against GetRootPath (shellctrls.pas
    :1536-1545). Ours matched absolute root-prefixed paths only, so a relative
    write silently did nothing at all. }
  FTree.Path := 'a';
  AssertTrue('a root-relative write lands on the right node',
    SamePath(FTree.Directory, FDirA));

  FTree.Path := 'a' + PathDelim + 'b';
  AssertTrue('...including a multi-segment one',
    SamePath(FTree.Directory, AppendPathDelim(FDirA) + 'b'));

  FTree.Path := FDirA;
  AssertTrue('...and an absolute one still works', SamePath(FTree.Directory, FDirA));
end;

{ shellctrls.pas:138 -- the tree enumerated [fotFolders] and nothing could change
  it, so the classic Explorer left pane (folders AND files) was impossible. }
procedure TShellTreeParityTest.ObjectTypesCanShowFilesAsLeaves;
var
  n: PTyTreeNode;
begin
  AssertTrue('the default matches LCL''s', FTree.ObjectTypes = [fotFolders]);
  n := NodeForPath(FRoot);
  FTree.Expanded[n] := True;
  AssertTrue('precondition: folders only, so the file is not a node',
    not HasChildNamed(n, 'leaf.txt'));

  FTree.ObjectTypes := [fotFolders, fotFiles];
  n := NodeForPath(FRoot);
  FTree.Expanded[n] := True;
  AssertTrue('files appear as leaves', HasChildNamed(n, 'leaf.txt'));
  AssertTrue('...alongside the folders', HasChildNamed(n, 'a'));

  FTree.ObjectTypes := [fotFolders];
  n := NodeForPath(FRoot);
  FTree.Expanded[n] := True;
  AssertTrue('and go away again', not HasChildNamed(n, 'leaf.txt'));
end;

procedure TShellTreeParityTest.ObjectTypesAndShowHiddenStayInSync;
begin
  AssertTrue('precondition', not FTree.ShowHidden);
  AssertTrue('the hidden bit is not in the set', not (fotHidden in FTree.ObjectTypes));
  FTree.ShowHidden := True;
  AssertTrue('ShowHidden:=True sets the bit', fotHidden in FTree.ObjectTypes);
  FTree.ObjectTypes := [fotFolders];
  AssertTrue('clearing the bit clears ShowHidden', not FTree.ShowHidden);
end;

{ shellctrls.pas:140 -- children arrived in raw FindFirst order with no way to ask
  for alphabetical or folders-first, though TyFsSortEntries had existed all along. }
procedure TShellTreeParityTest.FileSortTypeOrdersChildrenAlphabetically;
var
  n: PTyTreeNode;
begin
  AssertEquals('the default matches LCL''s', Ord(fstNone), Ord(FTree.FileSortType));
  FTree.FileSortType := fstAlphabet;
  n := NodeForPath(FRoot);
  FTree.Expanded[n] := True;
  AssertEquals('children come back in name order', 'a,alpha,zeta', ChildNames(n));
  { NOTE for whoever mutation-tests this: on NTFS (and any directory-indexed
    filesystem) FindFirst already hands names back in case-insensitive name order,
    so this assertion CANNOT distinguish "we sorted" from "it arrived sorted" --
    deleting the fstAlphabet arm leaves it green. The discriminating guard is
    FileSortTypeFoldersFirstPutsDirectoriesAhead below: folders-first puts leaf.txt
    after zeta, which no enumeration order produces. On ext4, where the raw order is
    effectively arbitrary, this one bites too. }
end;

procedure TShellTreeParityTest.FileSortTypeFoldersFirstPutsDirectoriesAhead;
var
  n: PTyTreeNode;
begin
  FTree.ObjectTypes := [fotFolders, fotFiles];
  FTree.FileSortType := fstFoldersFirst;
  n := NodeForPath(FRoot);
  FTree.Expanded[n] := True;
  AssertEquals('every folder precedes the file, each group name-ordered',
    'a,alpha,zeta,leaf.txt', ChildNames(n));
end;

{ shellctrls.pas:144. The ancestor's OnCompareNodes compares NODES (rendered text);
  ordering by extension, date or natural-numeric needs the file records. }
procedure TShellTreeParityTest.OnSortCompareTakesOverTheOrdering;
var
  n: PTyTreeNode;
begin
  FTree.OnSortCompare := @CompareByNameDesc;
  AssertEquals('assigning the comparator switches to fstCustom',
    Ord(fstCustom), Ord(FTree.FileSortType));
  n := NodeForPath(FRoot);
  FTree.Expanded[n] := True;
  AssertEquals('and the handler decides the order', 'zeta,alpha,a', ChildNames(n));

  { Clearing it must not leave fstCustom with nothing to call. }
  FTree.OnSortCompare := nil;
  AssertEquals('clearing drops back to unordered',
    Ord(fstNone), Ord(FTree.FileSortType));
end;

{ shellctrls.pas:143 -- there was no way to hide .git, a system junction or a
  symlink loop; the only filter was the coarse hidden attribute. }
procedure TShellTreeParityTest.OnAddItemCanVetoAFolder;
var
  n: PTyTreeNode;
begin
  FTree.OnAddItem := @HandleAddItem;
  FAddItemVeto := 'zeta';
  n := NodeForPath(FRoot);
  FTree.Expanded[n] := True;
  AssertTrue('the handler was consulted', FAddItemSeen > 0);
  AssertTrue('the vetoed folder is not a node', not HasChildNamed(n, 'zeta'));
  AssertTrue('its siblings still are', HasChildNamed(n, 'a'));
end;

{ shellctrls.pas:133 -- one branch, not the whole tree. }
procedure TShellTreeParityTest.RefreshNodeReReadsOnlyThatBranch;
var
  nRoot, nA: PTyTreeNode;
begin
  { ecmKeepChildren so nothing re-reads by itself and the scoping is observable. }
  FTree.ExpandCollapseMode := ecmKeepChildren;
  nRoot := NodeForPath(FRoot);
  FTree.Expanded[nRoot] := True;
  nA := NodeForPath(FDirA);
  FTree.Expanded[nA] := True;

  ForceDirectoriesUTF8(AppendPathDelim(FRoot) + 'fresh_top');
  ForceDirectoriesUTF8(AppendPathDelim(FDirA) + 'fresh_sub');

  nA := NodeForPath(FDirA);
  FTree.Refresh(nA);

  nA := NodeForPath(FDirA);
  AssertTrue('the refreshed branch picked the new child up',
    HasChildNamed(nA, 'fresh_sub'));
  nRoot := NodeForPath(FRoot);
  AssertTrue('and the rest of the tree was left alone',
    not HasChildNamed(nRoot, 'fresh_top'));
end;

{ shellctrls.pas:134 -- AStartDir limits the refresh to one subtree. }
procedure TShellTreeParityTest.UpdateViewStartDirLimitsTheRefreshToOneSubtree;
var
  nRoot, nA: PTyTreeNode;
begin
  FTree.ExpandCollapseMode := ecmKeepChildren;
  nRoot := NodeForPath(FRoot);
  FTree.Expanded[nRoot] := True;
  nA := NodeForPath(FDirA);
  FTree.Expanded[nA] := True;

  ForceDirectoriesUTF8(AppendPathDelim(FRoot) + 'fresh_top');
  ForceDirectoriesUTF8(AppendPathDelim(FDirA) + 'fresh_sub');

  FTree.UpdateView(FDirA);
  nA := NodeForPath(FDirA);
  AssertTrue('the named subtree was refreshed', HasChildNamed(nA, 'fresh_sub'));
  nRoot := NodeForPath(FRoot);
  AssertTrue('everything above it was not', not HasChildNamed(nRoot, 'fresh_top'));

  FTree.UpdateView;
  nRoot := NodeForPath(FRoot);
  AssertTrue('...and the no-argument form still refreshes everything',
    HasChildNamed(nRoot, 'fresh_top'));
end;

{ shellctrls.pas:118. Ours was hard-wired STRICTER than ecmKeepChildren: a node
  enumerated once stayed that way for the control's whole lifetime, so anything
  created or deleted afterwards never appeared and collapse+re-expand did not help. }
procedure TShellTreeParityTest.ExpandCollapseModeRefreshedExpandingReReadsOnEachExpand;
var
  n: PTyTreeNode;
begin
  AssertEquals('the default matches LCL''s',
    Ord(ecmRefreshedExpanding), Ord(FTree.ExpandCollapseMode));

  n := NodeForPath(FRoot);
  FTree.Expanded[n] := True;
  AssertTrue('precondition', not HasChildNamed(n, 'later'));
  FTree.Expanded[n] := False;

  ForceDirectoriesUTF8(AppendPathDelim(FRoot) + 'later');
  FTree.Expanded[n] := True;
  AssertTrue('a re-expand re-reads the directory', HasChildNamed(n, 'later'));
  AssertTrue('...and the old children are still there too',
    HasChildNamed(n, 'a') and HasChildNamed(n, 'zeta'));
end;

procedure TShellTreeParityTest.ExpandCollapseModeKeepChildrenIsTheOldBehaviour;
var
  n: PTyTreeNode;
begin
  FTree.ExpandCollapseMode := ecmKeepChildren;
  n := NodeForPath(FRoot);
  FTree.Expanded[n] := True;
  FTree.Expanded[n] := False;
  ForceDirectoriesUTF8(AppendPathDelim(FRoot) + 'later');
  FTree.Expanded[n] := True;
  AssertTrue('keeping children means the cached list is reused',
    not HasChildNamed(n, 'later'));
end;

{ shellctrls.pas:135 -- the only route to "no icons" was to overwrite Images after
  construction, and there was no way to ask for none at all. }
procedure TShellTreeParityTest.UseBuiltinIconsOffDetachesTheBuiltInList;
begin
  AssertTrue('default is on, like LCL''s', FTree.UseBuiltinIcons);
  AssertTrue('by default the tree carries its own list', FTree.Images <> nil);
  FTree.UseBuiltinIcons := False;
  AssertTrue('with the switch off there is no icon list at all', FTree.Images = nil);
  FTree.UseBuiltinIcons := True;
  AssertTrue('and it comes back', FTree.Images <> nil);
end;

{ ===========================================================================
  TShellLinkParityTest
  =========================================================================== }

procedure TShellLinkParityTest.SetUp;
begin
  FRoot := ChompPathDelim(AppendPathDelim(GetUserDir) +
                          'typarityshelllink_' + IntToStr(GetProcessID));
  if DirectoryExistsUTF8(FRoot) then DeleteDirectory(FRoot, False);
  ForceDirectoriesUTF8(FRoot);
  FDirA := AppendPathDelim(FRoot) + 'a';
  ForceDirectoriesUTF8(FDirA);

  FTree  := TTyShellTreeView.Create(nil);
  FList  := TTyShellListView.Create(nil);
  FCombo := TTyFilterComboBox.Create(nil);
  AssertTrue('fixture reachable (no hidden ancestor)', FTree.SelectPath(FRoot));
end;

procedure TShellLinkParityTest.TearDown;
begin
  FreeAndNil(FCombo);
  FreeAndNil(FTree);
  FreeAndNil(FList);
  if (FRoot <> '') and DirectoryExistsUTF8(FRoot) then DeleteDirectory(FRoot, False);
end;

{ shellctrls.pas:139 -- the canonical two-control file browser could not be
  assembled in the Object Inspector; every app hand-wrote the OnPathChange glue. }
procedure TShellLinkParityTest.TreeSelectionDrivesTheLinkedList;
begin
  FTree.ShellListView := FList;
  { Wiring alone adopts the tree's current selection -- the designer case. }
  AssertTrue('assigning the link pushed the current path',
    SamePath(FList.Directory, FRoot));

  AssertTrue('precondition', FTree.SelectPath(FDirA));
  AssertTrue('selecting a folder set the list''s directory with no glue',
    SamePath(FList.Directory, FDirA));
end;

procedure TShellLinkParityTest.TreeUnlinksTheListWhenItIsFreed;
begin
  FTree.ShellListView := FList;
  FreeAndNil(FList);
  AssertTrue('Notification nils a link to a freed view', FTree.ShellListView = nil);
  { ...and the tree still works rather than walking a dead pointer. }
  AssertTrue('the tree survives its partner', FTree.SelectPath(FDirA));
end;

{ shellctrls.pas:301 -- the reverse direction had no seam at all. }
procedure TShellLinkParityTest.ListNavigationDrivesTheLinkedTree;
begin
  FList.ShellTreeView := FTree;
  FList.Directory := FDirA;
  AssertTrue('the tree followed the list into the folder',
    SamePath(FTree.Directory, FDirA));
end;

procedure TShellLinkParityTest.ListUnlinksTheTreeWhenItIsFreed;
begin
  FList.ShellTreeView := FTree;
  FreeAndNil(FTree);
  AssertTrue('Notification nils a link to a freed tree', FList.ShellTreeView = nil);
  FList.Directory := FRoot;
  AssertTrue('the list survives its partner', SamePath(FList.Directory, FRoot));
end;

{ Both directions wired at once. LCL guards this cascade with FLockUpdate
  (shellctrls.pas:2003-2011); without a guard it is unbounded recursion, so the
  assertion that matters most is simply that control returns here at all. }
procedure TShellLinkParityTest.TwoWayLinkSettlesInsteadOfRecursing;
begin
  FTree.ShellListView := FList;
  FList.ShellTreeView := FTree;

  FTree.SelectPath(FDirA);
  AssertTrue('tree -> list settles', SamePath(FList.Directory, FDirA));
  AssertTrue('...and the tree kept its own selection',
    SamePath(FTree.Directory, FDirA));

  FList.Directory := FRoot;
  AssertTrue('list -> tree settles', SamePath(FTree.Directory, FRoot));
  AssertTrue('...and the list kept its own directory',
    SamePath(FList.Directory, FRoot));
end;

{ filectrl.pp:167 -- the whole point of the control. Without it every filter combo
  needed a hand-written OnFilterChange handler copying Mask into the list. }
procedure TShellLinkParityTest.FilterComboPushesItsMaskIntoTheLinkedList;
begin
  FCombo.ShellListView := FList;
  FCombo.Filter := 'Text|*.txt|All|*.*';
  AssertEquals('writing Filter pushed the active mask', '*.txt', FList.Mask);
  FCombo.FilterIndex := 2;
  AssertEquals('picking a row pushed the new mask', '*.*', FList.Mask);
  FCombo.FilterIndex := 1;
  AssertEquals('...and keeps pushing', '*.txt', FList.Mask);
end;

procedure TShellLinkParityTest.FilterComboUnlinksTheListWhenItIsFreed;
begin
  FCombo.ShellListView := FList;
  FreeAndNil(FList);
  AssertTrue('Notification nils a link to a freed view (filectrl.pp:565)',
    FCombo.ShellListView = nil);
  { ...and a later pick does not walk the dead pointer. }
  FCombo.Filter := 'Text|*.txt';
  AssertEquals('the combo still works alone', '*.txt', FCombo.Mask);
end;

{ filectrl.pp:163-164 -- a public CLASS method usable with no instance. Ours had
  the parser only as a free function returning a fresh record array, so there was
  no way to fill (or append to) a caller's TStrings. }
procedure TShellLinkParityTest.ConvertFilterToStringsFillsACallerSuppliedList;
var
  sl: TStringList;
begin
  sl := TStringList.Create;
  try
    TTyFilterComboBox.ConvertFilterToStrings('Text|*.txt|All|*.*', sl,
      True, True, False);
    AssertEquals('descriptions only', 2, sl.Count);
    AssertEquals('', 'Text', sl[0]);
    AssertEquals('', 'All', sl[1]);

    TTyFilterComboBox.ConvertFilterToStrings('Text|*.txt|All|*.*', sl,
      True, False, True);
    AssertEquals('patterns only', 2, sl.Count);
    AssertEquals('', '*.txt', sl[0]);
    AssertEquals('', '*.*', sl[1]);

    TTyFilterComboBox.ConvertFilterToStrings('Text|*.txt', sl, True, True, True);
    AssertEquals('both, description then pattern', 2, sl.Count);
    AssertEquals('', 'Text', sl[0]);
    AssertEquals('', '*.txt', sl[1]);
  finally
    sl.Free;
  end;
end;

procedure TShellLinkParityTest.ConvertFilterToStringsAppendsWhenAskedNotToClear;
var
  sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.Add('keep me');
    { The mode TyFsParseFilter cannot express: merge into an existing list. }
    TTyFilterComboBox.ConvertFilterToStrings('Text|*.txt', sl, False, True, False);
    AssertEquals('AClearStrings=False appends', 2, sl.Count);
    AssertEquals('the existing row survived', 'keep me', sl[0]);
    AssertEquals('', 'Text', sl[1]);
  finally
    sl.Free;
  end;
end;

initialization
  RegisterTest(TShellListParityTest);
  RegisterTest(TShellTreeParityTest);
  RegisterTest(TShellLinkParityTest);
end.
