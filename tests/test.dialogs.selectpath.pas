unit test.dialogs.selectpath;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry,
  tyControls.Dialogs, tyControls.TreeView, tyControls.Dialogs.SelectPath;
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

initialization
  RegisterTest(TSelectPathFsTest);
  RegisterTest(TSelectPathBuildTest);
end.
