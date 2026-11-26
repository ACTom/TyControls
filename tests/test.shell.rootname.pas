unit test.shell.rootname;
{$mode objfpc}{$H+}

{ #250: a drive is named C: wherever the library shows one.

  TyFsRoots was documented to give a drive the Display 'C:', and made it with ChompPathDelim,
  which keeps the delimiter of a root: the name came out as 'C:\', the same as the path. The
  folder tree and the folder box show that name, so both showed 'C:\'. The folder picker has
  roots of its own and showed the whole path of one for want of a last part.

  There is one rule now, TyFsRootName, and the three places are asked here whether they show
  what it says. What each should show is worked out in this unit, not asked of the function:
  the root without its trailing delimiter, or the root itself where that leaves nothing.

  The drive used is the one the temporary folder is on. Where roots have no delimiter to lose
  (the Unix '/') these tests hold before and after; the two about the function itself say what
  it does with a drive on any host. }

interface

uses
  Classes, SysUtils, Forms, Controls, LazFileUtils, fpcunit, testregistry,
  tyControls.FileSystem, tyControls.TreeView, tyControls.ShellTreeView,
  tyControls.ShellComboBox, tyControls.Dialogs, tyControls.Dialogs.SelectPath;

type
  TRootNameTest = class(TTestCase)
  private
    FForm: TForm;
    { The root the temporary folder is under, as TyFsRoots lists it: 'C:\', or '/'. }
    function ARoot: string;
    { What a root should be shown as. }
    function Named(const ARootPath: string): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure ARootIsNamedWithoutItsDelimiter;
    procedure ARootThatIsOnlyItsDelimiterIsItsOwnName;
    procedure TheListOfRootsNamesEachDriveSoAndKeepsItsPath;
    procedure TheFolderTreeShowsADriveByThatName;
    procedure AFolderTreeScopedToADriveShowsItSoToo;
    procedure TheFolderBoxShowsItSoAndStillHandsOutThePath;
    procedure TheFolderPickerShowsItSo;
    procedure AFolderPickerRootedAtADriveShowsItSoToo;
  end;

implementation

type
  TTreeAcc = class(TTyShellTreeView);
  TBoxAcc = class(TTyShellComboBox);

procedure TRootNameTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
end;

procedure TRootNameTest.TearDown;
begin
  FForm.Free;
end;

function TRootNameTest.ARoot: string;
var
  r: TTyFsRootArray;
  tmp: string;
  i: Integer;
begin
  Result := '';
  tmp := ExpandFileNameUTF8(GetTempDir);
  r := TyFsRoots;
  for i := 0 to High(r) do
    if (r[i].Kind in [rkDrive, rkRoot])
       and SameFileName(Copy(tmp, 1, Length(r[i].Path)), r[i].Path) then Exit(r[i].Path);
  Fail('precondition: the temporary folder ' + tmp + ' is under none of the roots');
end;

function TRootNameTest.Named(const ARootPath: string): string;
begin
  Result := ExcludeTrailingPathDelimiter(ARootPath);
  if Result = '' then Result := ARootPath;
end;

procedure TRootNameTest.ARootIsNamedWithoutItsDelimiter;
begin
  AssertEquals('a drive with its delimiter', 'X:', TyFsRootName('X:' + PathDelim));
  AssertEquals('one that is given without it', 'X:', TyFsRootName('X:'));
  AssertEquals('a share', PathDelim + PathDelim + 'box' + PathDelim + 'pub',
    TyFsRootName(PathDelim + PathDelim + 'box' + PathDelim + 'pub' + PathDelim));
end;

procedure TRootNameTest.ARootThatIsOnlyItsDelimiterIsItsOwnName;
begin
  AssertEquals('the root of a Unix file system', '/', TyFsRootName('/'));
  AssertEquals('nothing is the name of nothing', '', TyFsRootName(''));
end;

procedure TRootNameTest.TheListOfRootsNamesEachDriveSoAndKeepsItsPath;
var
  r: TTyFsRootArray;
  i, n: Integer;
begin
  r := TyFsRoots;
  n := 0;
  for i := 0 to High(r) do
    if r[i].Kind in [rkDrive, rkRoot] then
    begin
      Inc(n);
      AssertEquals('the name of ' + r[i].Path, Named(r[i].Path), r[i].Display);
      AssertTrue('the path of ' + r[i].Display + ' still ends in its delimiter',
        r[i].Path[Length(r[i].Path)] in AllowDirectorySeparators);
    end;
  AssertTrue('precondition: this machine has a drive or a root', n > 0);
end;

procedure TRootNameTest.TheFolderTreeShowsADriveByThatName;
var
  t: TTreeAcc;
  r: TTyFsRootArray;
  n: PTyTreeNode;
  shown: TStringList;
  s: string;
  i: Integer;
begin
  r := TyFsRoots;
  shown := TStringList.Create;
  t := TTreeAcc.Create(FForm);
  try
    t.Parent := FForm;
    n := t.GetFirst;
    while n <> nil do
    begin
      s := '';
      t.DoGetText(n, s);
      shown.Add(s);
      n := t.GetNextSibling(n);
    end;
    AssertEquals('precondition: one row at the top for each root', Length(r), shown.Count);
    for i := 0 to High(r) do
      if r[i].Kind in [rkDrive, rkRoot] then
        AssertEquals('the row of ' + r[i].Path, Named(r[i].Path), shown[i]);
  finally
    shown.Free;
  end;
end;

procedure TRootNameTest.AFolderTreeScopedToADriveShowsItSoToo;
var
  t: TTreeAcc;
  n: PTyTreeNode;
  s, root: string;
begin
  { Scoped, the tree has no list of roots to take a name from: its one top row is named
    from its path, which Root keeps without a delimiter. This held before #250 and is here
    so that the two kinds of tree are seen to agree. }
  root := ARoot;
  t := TTreeAcc.Create(FForm);
  t.Parent := FForm;
  t.Root := root;
  n := t.GetFirst;
  AssertTrue('precondition: the scoped tree has one top row',
    (n <> nil) and (t.GetNextSibling(n) = nil));
  s := '';
  t.DoGetText(n, s);
  AssertEquals('the row of the root', Named(root), s);
end;

procedure TRootNameTest.TheFolderBoxShowsItSoAndStillHandsOutThePath;
var
  c: TBoxAcc;
  root: string;
begin
  root := ARoot;
  c := TBoxAcc.Create(FForm);
  c.Parent := FForm;
  c.Directory := root;
  AssertTrue('precondition: its row is the selected one', c.ItemIndex >= 0);
  AssertEquals('the row of the root', Named(root), c.Items[c.ItemIndex]);
  AssertEquals('the closed field', Named(root), c.FieldCaption);
  AssertEquals('the directory the box is at is the root, delimiter and all', root, c.Directory);
  AssertTrue('and that is what it hands out', SameFileName(root, c.SelectedPath));
end;

procedure TRootNameTest.TheFolderPickerShowsItSo;
var
  d: TTySelectPathForm;
  root, tmp: string;
  node: PTyTreeNode;
  shown: string;
  n: Integer;
begin
  root := ARoot;
  d := TyBuildSelectPathDialog('Folder', '');
  try
    { its top rows are the drives: every one by its name, this root among them }
    shown := '';
    n := 0;
    node := d.Tree.GetFirst;
    while node <> nil do
    begin
      Inc(n);
      shown := shown + '[' + d.NodeText(node) + ']';
      node := d.Tree.GetNextSibling(node);
    end;
    AssertTrue('precondition: the picker lists roots', n > 0);
    AssertTrue('the root is listed as ' + Named(root) + ', among ' + shown,
      Pos('[' + Named(root) + ']', shown) > 0);
    if Named(root) <> root then
      AssertEquals('and not by its path, ' + root + ', among ' + shown,
        0, Pos('[' + root + ']', shown));
    { a folder is still shown by the last part of its path }
    tmp := ChompPathDelim(ExpandFileNameUTF8(GetTempDir));
    d.Directory := tmp;
    node := d.Tree.FocusedNode;
    AssertTrue('precondition: the picker went to the temporary folder',
      (node <> nil) and SameFileName(tmp, d.Directory));
    AssertEquals('a folder', ExtractFileName(tmp), d.NodeText(node));
  finally
    d.Free;
  end;
end;

procedure TRootNameTest.AFolderPickerRootedAtADriveShowsItSoToo;
var
  d: TTySelectPathForm;
  root: string;
  node: PTyTreeNode;
begin
  root := ARoot;
  d := TyBuildSelectPathDialog('Folder', root);
  try
    node := d.Tree.GetFirst;
    AssertTrue('precondition: the picker has the root as its one top row',
      (node <> nil) and (d.Tree.GetNextSibling(node) = nil));
    AssertEquals('the row of the root', Named(root), d.NodeText(node));
  finally
    d.Free;
  end;
end;

initialization
  RegisterTest(TRootNameTest);
end.
