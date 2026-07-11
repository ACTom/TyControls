unit test.dialogs.filedialog;
{ Headless tests for the ONLY headless-testable surface of the phase-7 file
  dialogs: the pure resolver

    function TyFileDialogResolveName(ASaveMode: Boolean;
      const ADir, ATyped, ASelected, ADefaultExt: string): string;

  The dialog FORM and its windowed child controls cannot be created under the
  console test runner (no win32 handle), so nothing here instantiates a form or
  a component -- every rule from the plan's "pure resolver function" section is
  pinned against the pure function alone.

  Semantics under test (plan lines):
    Save  : bare name expands against ADir + ADefaultExt appended when the
            resolved name has no extension (== TyFsResolveSaveName, cross-checked).
    Open  : a NON-EMPTY typed name always wins (directory-bearing verbatim, else a
            bare name expanded against ADir) -- it is what the user edits in the name
            box; only an EMPTY box falls back to ASelected (the focused item); all
            empty -> ''. }

{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry,
  tyControls.FileSystem, tyControls.Dialogs.FileDialog;
type
  TFileDialogResolveTest = class(TTestCase)
  private
    FDir: string;          { process-unique temp dir, holds a real 'a.txt' }
    FFile: string;         { FDir + PathDelim + 'a.txt' }
    { trailing-delimiter- and case-insensitive path equality that also
      normalises '/' vs '\', since the function may return either form }
    function SamePath(const A, B: string): Boolean;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { Save branch }
    procedure TestSaveBareNameGetsDirAndDefaultExt;
    procedure TestSaveKeepsExistingExtension;
    procedure TestSaveEmptyNameIsEmpty;
    { Open branch }
    procedure TestOpenEmptyTypedUsesSelected;
    procedure TestOpenBareTypedExpandsAgainstDir;
    procedure TestOpenTypedBeatsSelected;
    procedure TestOpenTypedWithPathVerbatim;
    procedure TestOpenAllEmptyIsEmpty;
  end;
implementation

function TFileDialogResolveTest.SamePath(const A, B: string): Boolean;
  function Norm(const S: string): string;
  begin
    Result := StringReplace(S, '/', PathDelim, [rfReplaceAll]);
    Result := StringReplace(Result, '\', PathDelim, [rfReplaceAll]);
    Result := ExcludeTrailingPathDelimiter(Result);
  end;
begin
  Result := SameText(Norm(A), Norm(B));
end;

procedure TFileDialogResolveTest.SetUp;
begin
  { process-unique so parallel/other suites never collide }
  FDir := IncludeTrailingPathDelimiter(GetTempDir)
        + Format('tyfiledlg_%d_%d', [PtrUInt(Self), Random(MaxInt)]);
  ForceDirectories(FDir);
  FFile := FDir + PathDelim + 'a.txt';
  with TStringList.Create do
    try Add('x'); SaveToFile(FFile); finally Free; end;
end;

procedure TFileDialogResolveTest.TearDown;
begin
  DeleteFile(FFile);
  RemoveDir(FDir);
end;

{ Save, bare name 'report', defExt 'txt' -> <dir>/report.txt, and this must
  equal TyFsResolveSaveName (the Save branch IS that helper). Plan:
  "Save, bare name report ... -> <tmp>/report.txt (= TyFsResolveSaveName, cross-checked)". }
procedure TFileDialogResolveTest.TestSaveBareNameGetsDirAndDefaultExt;
var got, expect: string;
begin
  got    := TyFileDialogResolveName(True, FDir, 'report', '', 'txt');
  expect := TyFsResolveSaveName(FDir, 'report', 'txt');
  AssertTrue('bare save name resolves under dir with .txt',
    SamePath(got, FDir + PathDelim + 'report.txt'));
  AssertTrue('save branch matches TyFsResolveSaveName', SamePath(got, expect));
end;

{ Save, 'report.md' + defExt 'txt' -> <dir>/report.md (existing ext kept). Plan:
  "Save, report.md + defExt txt -> <tmp>/report.md (existing extension left alone)". }
procedure TFileDialogResolveTest.TestSaveKeepsExistingExtension;
var got: string;
begin
  got := TyFileDialogResolveName(True, FDir, 'report.md', '', 'txt');
  AssertTrue('existing extension is kept, not overridden',
    SamePath(got, FDir + PathDelim + 'report.md'));
end;

{ Save, empty typed -> ''. Plan: "Save, empty name -> ''". }
procedure TFileDialogResolveTest.TestSaveEmptyNameIsEmpty;
begin
  AssertEquals('empty save name -> empty result',
    '', TyFileDialogResolveName(True, FDir, '', '', 'txt'));
end;

{ Open, ATyped='' , ASelected=<dir>/a.txt -> <dir>/a.txt (the focused item).
  Plan: "Open, ATyped='', ASelected=<tmp>/a.txt -> <tmp>/a.txt". }
procedure TFileDialogResolveTest.TestOpenEmptyTypedUsesSelected;
var got: string;
begin
  got := TyFileDialogResolveName(False, FDir, '', FFile, '');
  AssertTrue('empty typed falls back to the selected item',
    SamePath(got, FFile));
end;

{ Open, ATyped='b.txt' (bare) + dir -> <dir>/b.txt (expanded against dir). Plan:
  "Open, ATyped='b.txt' (bare name), dir <tmp> -> <tmp>/b.txt (expanded against dir)". }
procedure TFileDialogResolveTest.TestOpenBareTypedExpandsAgainstDir;
var got: string;
begin
  got := TyFileDialogResolveName(False, FDir, 'b.txt', '', '');
  AssertTrue('a bare typed name expands against the current dir',
    SamePath(got, FDir + PathDelim + 'b.txt'));
end;

{ Open, a non-empty typed name beats a live selection: type 'z.txt' while 'a.txt' is
  the focused item -> <dir>/z.txt, not the selection. The name box is what the user
  edits, so it wins. (The contract left the bare-typed-vs-selected conflict unpinned;
  this pins the typed-wins choice.) }
procedure TFileDialogResolveTest.TestOpenTypedBeatsSelected;
var got: string;
begin
  got := TyFileDialogResolveName(False, FDir, 'z.txt', FFile, '');
  AssertTrue('a typed name overrides the current selection',
    SamePath(got, FDir + PathDelim + 'z.txt'));
end;

{ Open, ATyped=<abs>/c.txt (carries a directory part) -> returned verbatim. Plan:
  "Open, ATyped=<abs>/c.txt (carries a path) -> verbatim". }
procedure TFileDialogResolveTest.TestOpenTypedWithPathVerbatim;
var typed, got: string;
begin
  typed := FDir + PathDelim + 'c.txt';        { a path with a directory part }
  got   := TyFileDialogResolveName(False, FDir, typed, '', '');
  AssertTrue('a directory-bearing typed path is kept as-is',
    SamePath(got, typed));
end;

{ Open, ATyped='' and ASelected='' -> ''. Plan: "Open, ATyped='' and ASelected='' -> ''". }
procedure TFileDialogResolveTest.TestOpenAllEmptyIsEmpty;
begin
  AssertEquals('nothing typed and nothing selected -> empty result',
    '', TyFileDialogResolveName(False, FDir, '', '', ''));
end;

initialization
  Randomize;
  RegisterTest(TFileDialogResolveTest);
end.
