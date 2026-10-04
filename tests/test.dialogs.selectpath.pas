unit test.dialogs.selectpath;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Forms, Controls, Dialogs, LazFileUtils, fpcunit, testregistry,
  tyControls.Dialogs, tyControls.TreeView, tyControls.Dialogs.SelectPath, tyControls.Button,
  tyControls.StrConsts;
type
  TSelectPathFsTest = class(TTestCase)
  private
    FRoot: string;
    procedure MakeTree;
    procedure KillTree;
  published
    procedure TestSubdirectoriesSortedFilesExcluded;
    procedure TestPathHasSubdir;
  end;

  TSelectPathBuildTest = class(TTestCase)
  published
    procedure TestBuildRootedTreeHasButtons;
    procedure TestExpandPopulatesChildren;
    procedure TestCreateSubfolderShowsAndFocuses;
    procedure TestCreateSubfolderUnderCollapsedParent;
    procedure TestDirectoryPreselectsPath;
  end;

  { LCL's TOpenOptions on the folder picker (#28). }
  TSelectPathOptionsTest = class(TTestCase)
  private
    FDir: string;
    FHelpSender: TObject;
    procedure HandleHelp(Sender: TObject);
    function HelpOf(AForm: TTySelectPathForm): TTyButton;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAMissingFolderWithNoOptionsIsLeftToTheTree;
    procedure TestPathMustExistLooksAtTheParent;
    procedure TestFileMustExistLooksAtTheFolder;
    procedure TestCreatePromptOffersToCreate;
    procedure TestExistingFoldersPass;
    procedure TestNoReadOnlyReturn;
    procedure TestBuildFormCarriesTheOptions;
    procedure TestShowHelp;
    procedure TestDefaultsAreNotWritten;
  end;
implementation

procedure TSelectPathFsTest.MakeTree;
begin
  FRoot := IncludeTrailingPathDelimiter(GetTempDir) + 'tyselpath_' + IntToStr(PtrUInt(Self));
  ForceDirectories(FRoot + PathDelim + 'beta');
  ForceDirectories(FRoot + PathDelim + 'alpha' + PathDelim + 'child');
  with TStringList.Create do try Add('x'); SaveToFile(FRoot + PathDelim + 'note.txt'); finally Free; end;
end;

procedure TSelectPathFsTest.KillTree;
begin
  RemoveDir(FRoot + PathDelim + 'alpha' + PathDelim + 'child');
  RemoveDir(FRoot + PathDelim + 'alpha');
  RemoveDir(FRoot + PathDelim + 'beta');
  DeleteFile(FRoot + PathDelim + 'note.txt');
  RemoveDir(FRoot);
end;

procedure TSelectPathFsTest.TestSubdirectoriesSortedFilesExcluded;
var a: TStringArray;
begin
  MakeTree;
  try
    a := TySubdirectories(FRoot);
    AssertEquals('two subdirs', 2, Length(a));
    AssertEquals('sorted 0', 'alpha', a[0]);
    AssertEquals('sorted 1', 'beta', a[1]);   // file 'note.txt' excluded
  finally KillTree; end;
end;

procedure TSelectPathFsTest.TestPathHasSubdir;
begin
  MakeTree;
  try
    AssertTrue('root has subdir', TyPathHasSubdir(FRoot));
    AssertTrue('alpha has child', TyPathHasSubdir(FRoot + PathDelim + 'alpha'));
    AssertFalse('beta empty', TyPathHasSubdir(FRoot + PathDelim + 'beta'));
  finally KillTree; end;
end;

{ TSelectPathBuildTest }

procedure TSelectPathBuildTest.TestBuildRootedTreeHasButtons;
var d: TTySelectPathForm; root: string;
begin
  root := IncludeTrailingPathDelimiter(GetTempDir) + 'tyselpath_build';
  ForceDirectories(root + PathDelim + 'sub');
  try
    d := TyBuildSelectPathDialog('Choose folder', root);
    try
      AssertTrue('tree created', d.Tree <> nil);
      AssertTrue('resizable', d.Resizable);
      AssertTrue('at least 3 buttons (New Folder + OK + Cancel)', TyDialogButtonCount(d) >= 3);
    finally d.Free; end;
  finally RemoveDir(root + PathDelim + 'sub'); RemoveDir(root); end;
end;

{ Bonus: the lazy population actually works headlessly. The imperative
  OnExpanding+AddChild model expands via Expanded[node]:=True with no window
  handle (same idiom as the treeview drag tab). Build a single-root tree, expand
  the root, and assert the materialised children match TySubdirectories(root). }
procedure TSelectPathBuildTest.TestExpandPopulatesChildren;
var
  d: TTySelectPathForm; root: string;
  rootNode, child: PTyTreeNode;
  subs: TStringArray; n: Integer;
begin
  root := IncludeTrailingPathDelimiter(GetTempDir) + 'tyselpath_expand';
  ForceDirectories(root + PathDelim + 'alpha');
  ForceDirectories(root + PathDelim + 'beta');
  try
    d := TyBuildSelectPathDialog('Choose folder', root);
    try
      rootNode := d.Tree.GetFirst;                 // the single root node
      AssertTrue('root node exists', rootNode <> nil);
      d.Tree.Expanded[rootNode] := True;           // lazy-populate (headless)
      AssertTrue('root is expanded', d.Tree.Expanded[rootNode]);

      subs := TySubdirectories(root);
      AssertEquals('two subdirs on disk', 2, Length(subs));

      { count materialised children }
      n := 0;
      child := d.Tree.GetFirstChild(rootNode);
      while child <> nil do
      begin
        Inc(n);
        child := d.Tree.GetNextSibling(child);
      end;
      AssertEquals('child count matches subdirs', Length(subs), n);

      { first child renders the first subdir's name via the tree's OnGetText path }
      child := d.Tree.GetFirstChild(rootNode);
      AssertEquals('first child name', subs[0], d.NodeText(child));
    finally d.Free; end;
  finally
    RemoveDir(root + PathDelim + 'alpha');
    RemoveDir(root + PathDelim + 'beta');
    RemoveDir(root);
  end;
end;

{ The refresh gate: after CreateSubfolder the new folder must exist on disk AND
  appear as a materialised child of the parent (and be focused). This FAILS
  against the old collapse+SetChildCount(0)+InitNode+expand chain (which no-ops:
  SetChildCount clears nsHasChildren, InitNode early-exits on nsInitialized, so
  the expand bails and the child never appears) and PASSES with incremental add. }
procedure TSelectPathBuildTest.TestCreateSubfolderShowsAndFocuses;
var
  d: TTySelectPathForm; root: string;
  rootNode, child, newNode: PTyTreeNode;
  ok: Boolean;
begin
  root := IncludeTrailingPathDelimiter(GetTempDir) + 'tyselpath_mkdir';
  ForceDirectories(root + PathDelim + 'alpha');   // one pre-existing subdir
  try
    d := TyBuildSelectPathDialog('Choose folder', root);
    try
      rootNode := d.Tree.GetFirst;
      AssertTrue('root node exists', rootNode <> nil);
      d.Tree.Expanded[rootNode] := True;          // populate (root now has 'alpha')

      ok := d.CreateSubfolder(rootNode, 'newdir');
      AssertTrue('CreateSubfolder returned True', ok);
      AssertTrue('newdir exists on disk', DirectoryExists(root + PathDelim + 'newdir'));

      { a child node named 'newdir' is now present under the root }
      newNode := nil;
      child := d.Tree.GetFirstChild(rootNode);
      while child <> nil do
      begin
        if d.NodeText(child) = 'newdir' then begin newNode := child; Break; end;
        child := d.Tree.GetNextSibling(child);
      end;
      AssertTrue('newdir node present under root', newNode <> nil);
      AssertTrue('new folder is focused', d.Tree.FocusedNode = newNode);
    finally d.Free; end;
  finally
    RemoveDir(root + PathDelim + 'newdir');
    RemoveDir(root + PathDelim + 'alpha');
    RemoveDir(root);
  end;
end;

{ Covers the COLLAPSED / first-child branch of CreateSubfolder (the seed-dance):
  the parent 'outer' has NO subdirs yet (so nsHasChildren is false) and is
  materialised-but-collapsed. Creating its first child must clear + re-assert
  nsHasChildren and force a full populate so the new folder shows + is focused.
  Guards the trickiest refresh logic against future TreeView refactors. }
procedure TSelectPathBuildTest.TestCreateSubfolderUnderCollapsedParent;
var
  d: TTySelectPathForm; root, outer: string;
  rootNode, outerNode, child, newNode: PTyTreeNode;
  ok: Boolean; n: Integer;
begin
  root  := IncludeTrailingPathDelimiter(GetTempDir) + 'tyselpath_collapsed';
  outer := root + PathDelim + 'outer';
  ForceDirectories(outer);   // 'outer' exists but is EMPTY (no subdirs -> no nsHasChildren)
  try
    d := TyBuildSelectPathDialog('Choose folder', root);
    try
      rootNode := d.Tree.GetFirst;
      AssertTrue('root node exists', rootNode <> nil);
      d.Tree.Expanded[rootNode] := True;          // materialise 'outer' (but do NOT expand it)

      { locate the 'outer' child of root }
      outerNode := nil;
      child := d.Tree.GetFirstChild(rootNode);
      while child <> nil do
      begin
        if d.NodeText(child) = 'outer' then begin outerNode := child; Break; end;
        child := d.Tree.GetNextSibling(child);
      end;
      AssertTrue('outer node materialised under root', outerNode <> nil);
      AssertFalse('outer starts collapsed', d.Tree.Expanded[outerNode]);
      AssertEquals('outer has no children yet', 0, Integer(outerNode^.ChildCount));

      { first-child creation under the collapsed, childless 'outer' }
      ok := d.CreateSubfolder(outerNode, 'first');
      AssertTrue('CreateSubfolder returned True', ok);
      AssertTrue('outer/first exists on disk', DirectoryExists(outer + PathDelim + 'first'));

      { outer now reports exactly one child, named 'first' }
      n := 0; newNode := nil;
      child := d.Tree.GetFirstChild(outerNode);
      while child <> nil do
      begin
        Inc(n);
        if d.NodeText(child) = 'first' then newNode := child;
        child := d.Tree.GetNextSibling(child);
      end;
      AssertEquals('outer now has one child', 1, n);
      AssertTrue('first node present under outer', newNode <> nil);
      AssertTrue('new folder is focused', d.Tree.FocusedNode = newNode);
    finally d.Free; end;
  finally
    RemoveDir(outer + PathDelim + 'first');
    RemoveDir(outer);
    RemoveDir(root);
  end;
end;

{ Assigning Directory before ShowModal pre-selects a path: reveal (expand roots->leaf) + focus the
  node, so the dialog opens ON the current value instead of at the root. Reading it back gives the
  selection — the idiomatic in/out dialog property. }
procedure TSelectPathBuildTest.TestDirectoryPreselectsPath;
var
  d: TTySelectPathForm; root, target: string;
begin
  root   := IncludeTrailingPathDelimiter(GetTempDir) + 'tyselpath_initial';
  target := root + PathDelim + 'alpha' + PathDelim + 'child';
  ForceDirectories(target);
  try
    d := TyBuildSelectPathDialog('Choose folder', root);
    try
      d.Directory := target;   // in
      AssertTrue('a node is focused after Directory:=', d.Tree.FocusedNode <> nil);
      AssertEquals('the initial path is pre-selected',
        ExcludeTrailingPathDelimiter(target), ExcludeTrailingPathDelimiter(d.Directory));   // out
    finally d.Free; end;
  finally
    RemoveDir(target);
    RemoveDir(root + PathDelim + 'alpha');
    RemoveDir(root);
  end;
end;

{ TSelectPathOptionsTest }

procedure TSelectPathOptionsTest.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir)
        + Format('tyselopt_%d_%d', [PtrUInt(Self), Random(MaxInt)]);
  ForceDirectories(FDir);
end;

procedure TSelectPathOptionsTest.TearDown;
begin
  FileSetAttr(FDir, faDirectory);
  RemoveDir(FDir);
end;

procedure TSelectPathOptionsTest.HandleHelp(Sender: TObject);
begin
  FHelpSender := Sender;
end;

function TSelectPathOptionsTest.HelpOf(AForm: TTySelectPathForm): TTyButton;
var i: Integer;
begin
  Result := nil;
  for i := 0 to AForm.ButtonCount - 1 do
    if AForm.Buttons[i].Caption = rsMsgBtnHelp then Exit(AForm.Buttons[i]);
end;

procedure TSelectPathOptionsTest.TestAMissingFolderWithNoOptionsIsLeftToTheTree;
begin
  AssertTrue('3.0''s behaviour: OK goes through, the tree''s folder is the answer',
    TySelectPathCheck(FDir + PathDelim + 'none', []) = spcOK);
  AssertTrue('even two levels down', TySelectPathCheck(
    FDir + PathDelim + 'a' + PathDelim + 'b', [ofNoReadOnlyReturn]) = spcOK);
end;

procedure TSelectPathOptionsTest.TestPathMustExistLooksAtTheParent;
begin
  AssertTrue('the parent is missing', TySelectPathCheck(
    FDir + PathDelim + 'a' + PathDelim + 'b', [ofPathMustExist]) = spcParentMissing);
  AssertTrue('the parent exists: a new folder under it is fine', TySelectPathCheck(
    FDir + PathDelim + 'new', [ofPathMustExist]) = spcOK);
end;

procedure TSelectPathOptionsTest.TestFileMustExistLooksAtTheFolder;
begin
  AssertTrue('the folder itself is missing', TySelectPathCheck(
    FDir + PathDelim + 'new', [ofFileMustExist]) = spcMissing);
  AssertTrue('the parent first', TySelectPathCheck(
    FDir + PathDelim + 'a' + PathDelim + 'b', [ofPathMustExist, ofFileMustExist]) = spcParentMissing);
  AssertTrue('must exist beats offering to create', TySelectPathCheck(
    FDir + PathDelim + 'new', [ofFileMustExist, ofCreatePrompt]) = spcMissing);
end;

procedure TSelectPathOptionsTest.TestCreatePromptOffersToCreate;
begin
  AssertTrue('missing -> ask', TySelectPathCheck(
    FDir + PathDelim + 'new', [ofCreatePrompt]) = spcAskCreate);
end;

procedure TSelectPathOptionsTest.TestExistingFoldersPass;
begin
  AssertTrue('an existing folder passes every existence check', TySelectPathCheck(FDir,
    [ofPathMustExist, ofFileMustExist, ofCreatePrompt, ofNoReadOnlyReturn]) = spcOK);
  AssertTrue('an empty path is the tree''s business', TySelectPathCheck('', [ofFileMustExist]) = spcOK);
end;

procedure TSelectPathOptionsTest.TestNoReadOnlyReturn;
begin
  FileSetAttr(FDir, faDirectory or faReadOnly);
  if DirectoryIsWritable(FDir) then
    Ignore('cannot make a folder the user cannot write to here (Windows ignores read-only on folders)');
  AssertTrue('a folder that cannot be written to', TySelectPathCheck(FDir,
    [ofNoReadOnlyReturn]) = spcNotWritable);
  AssertTrue('without the option it is fine', TySelectPathCheck(FDir, []) = spcOK);
end;

procedure TSelectPathOptionsTest.TestBuildFormCarriesTheOptions;
var d: TTySelectPathDialog; f: TTySelectPathForm;
begin
  d := TTySelectPathDialog.Create(nil);
  try
    d.Root := FDir;
    d.Options := [ofPathMustExist, ofCreatePrompt];
    f := d.BuildForm;
    try
      AssertTrue('the form validates with the component''s options',
        f.Options = [ofPathMustExist, ofCreatePrompt]);
    finally f.Free; end;
  finally d.Free; end;
end;

procedure TSelectPathOptionsTest.TestShowHelp;
var d: TTySelectPathDialog; f: TTySelectPathForm;
begin
  FHelpSender := nil;
  d := TTySelectPathDialog.Create(nil);
  try
    d.Root := FDir;
    d.OnHelpClicked := @HandleHelp;
    f := d.BuildForm;
    try
      AssertTrue('no Help without ofShowHelp', HelpOf(f) = nil);
    finally f.Free; end;
    d.Options := [ofShowHelp];
    f := d.BuildForm;
    try
      AssertTrue('ofShowHelp adds Help', HelpOf(f) <> nil);
      HelpOf(f).Click;
      AssertTrue('the click reaches OnHelpClicked, Sender = the component', FHelpSender = d);
      AssertEquals('and leaves the dialog open', Ord(mrNone), Ord(f.ModalResult));
    finally f.Free; end;
  finally d.Free; end;
end;

procedure TSelectPathOptionsTest.TestDefaultsAreNotWritten;
var src: TForm; d: TTySelectPathDialog; ms, ts: TMemoryStream; L: TStringList;
begin
  src := TForm.CreateNew(nil);
  ms := TMemoryStream.Create;
  ts := TMemoryStream.Create;
  L := TStringList.Create;
  try
    d := TTySelectPathDialog.Create(src);
    d.Name := 'D';
    AssertTrue('default []', d.Options = []);
    ms.WriteComponent(src);
    ms.Position := 0;
    ObjectBinaryToText(ms, ts);
    ts.Position := 0;
    L.LoadFromStream(ts);
    AssertEquals('Options not written', 0, Pos('Options', L.Text));
    d.Options := [ofCreatePrompt];
    ms.Clear; ts.Clear;
    ms.WriteComponent(src);
    ms.Position := 0;
    ObjectBinaryToText(ms, ts);
    ts.Position := 0;
    L.LoadFromStream(ts);
    AssertTrue('set, it is written with LCL''s name', Pos('Options = [ofCreatePrompt]', L.Text) > 0);
  finally
    L.Free; ts.Free; ms.Free; src.Free;
  end;
end;

initialization
  RegisterTest(TSelectPathOptionsTest);
  RegisterTest(TSelectPathFsTest);
  RegisterTest(TSelectPathBuildTest);
end.
