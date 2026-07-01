unit test.dialogs.selectpath;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry, tyControls.Dialogs.SelectPath;
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

initialization
  RegisterTest(TSelectPathFsTest);
end.
