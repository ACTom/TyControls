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
uses Classes, SysUtils, Controls, fpcunit, testregistry,
  tyControls.FileSystem, tyControls.StrConsts, tyControls.ListView, tyControls.ShellListView,
  tyControls.Dialogs.FileDialog;
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
  { The form with its error box swapped for a list, so a refused name can be read instead of
    putting a modal window up. Everything else is the real form: the name box, the list, the
    OK path through CloseQuery. }
  TProbeFileDialog = class(TTyFileDialogForm)
  protected
    procedure ReportProblem(const AMsg: string); override;
  public
    Problems: TStringList;
  end;

  { fdoPathMustExist and fdoFileMustExist as LCL's TOpenDialog.CheckFile / CheckAllFiles apply
    them: for an open AND a save, the folder before the file, and for every file of a multiple
    selection. 3.0.0 never looked at fdoPathMustExist, checked fdoFileMustExist for an open only,
    and for a selection checked one name. }
  TFileDialogValidationTest = class(TTestCase)
  private
    FDir: string;
    FForm: TProbeFileDialog;
    FAsked: Boolean;
    FAnswer: Boolean;
    procedure CanClose(Sender: TObject; var ACanClose: Boolean);
    procedure Touch(const AName: string);
    procedure Dialog(ASave: Boolean; AOptions: TTyFileDialogOptions);
    function Accepts: Boolean;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestSaveRefusesAFolderThatIsNotThere;
    procedure TestSaveRefusesAMissingFileWhenItMustExist;
    procedure TestOpenRefusesAFolderThatIsNotThere;
    procedure TestOpenChecksEveryFileOfASelection;
    procedure TestOpenChecksTheTypedNameBesideASelection;
    procedure TestOnCanCloseIsNotAskedAboutARefusedName;
    procedure TestOnCanCloseHasTheLastWord;
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

{ TProbeFileDialog / TFileDialogValidationTest }

procedure TProbeFileDialog.ReportProblem(const AMsg: string);
begin
  Problems.Add(AMsg);
end;

procedure TFileDialogValidationTest.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir)
        + Format('tyfdcheck_%d_%d', [PtrUInt(Self), Random(MaxInt)]);
  ForceDirectories(FDir);
  FForm := nil;
end;

procedure TFileDialogValidationTest.TearDown;
var
  sr: TSearchRec;
begin
  if FForm <> nil then
  begin
    FForm.Problems.Free;
    FreeAndNil(FForm);
  end;
  if FindFirst(FDir + PathDelim + '*', faAnyFile, sr) = 0 then
  try
    repeat
      if (sr.Attr and faDirectory) = 0 then DeleteFile(FDir + PathDelim + sr.Name);
    until FindNext(sr) <> 0;
  finally
    FindClose(sr);
  end;
  RemoveDir(FDir);
end;

procedure TFileDialogValidationTest.Touch(const AName: string);
begin
  with TStringList.Create do
    try Add('x'); SaveToFile(FDir + PathDelim + AName); finally Free; end;
end;

procedure TFileDialogValidationTest.Dialog(ASave: Boolean; AOptions: TTyFileDialogOptions);
begin
  FForm := TProbeFileDialog.CreateNew(nil);
  FForm.Problems := TStringList.Create;
  FForm.SaveMode := ASave;
  FForm.Options := AOptions;
  FForm.InitialDir := FDir;
end;

{ What pressing OK does: CloseQuery with mrOK, which runs the validation. }
function TFileDialogValidationTest.Accepts: Boolean;
begin
  FForm.Problems.Clear;
  FForm.ModalResult := mrOK;
  Result := FForm.CloseQuery;
end;

procedure TFileDialogValidationTest.TestSaveRefusesAFolderThatIsNotThere;
begin
  Dialog(True, [fdoPathMustExist]);
  FForm.NameEdit.Text := FDir + PathDelim + 'nope' + PathDelim + 'x.txt';
  AssertFalse('a save into a folder that is not there is refused', Accepts);
  AssertEquals('and the user is told which folder',
    Format(rsFdPathMustExist, [FDir + PathDelim + 'nope']), FForm.Problems.Text.Trim);
  FForm.NameEdit.Text := FDir + PathDelim + 'new.txt';
  AssertTrue('a new file in a folder that is there is fine', Accepts);
  AssertEquals('and nothing is said', 0, FForm.Problems.Count);
end;

procedure TFileDialogValidationTest.TestSaveRefusesAMissingFileWhenItMustExist;
begin
  Touch('a.txt');
  Dialog(True, [fdoFileMustExist]);
  FForm.NameEdit.Text := 'missing.txt';
  AssertFalse('fdoFileMustExist holds for a save too, as in LCL', Accepts);
  AssertEquals('one message', 1, FForm.Problems.Count);
  AssertTrue('naming the file: ' + FForm.Problems.Text, Pos('missing.txt', FForm.Problems[0]) > 0);
  FForm.NameEdit.Text := 'a.txt';
  AssertTrue('an existing file passes', Accepts);
end;

procedure TFileDialogValidationTest.TestOpenRefusesAFolderThatIsNotThere;
begin
  Dialog(False, [fdoPathMustExist]);
  FForm.NameEdit.Text := FDir + PathDelim + 'nope' + PathDelim + 'x.txt';
  AssertFalse('an open from a folder that is not there is refused', Accepts);
  AssertEquals('and the message is about the folder, not the file',
    Format(rsFdPathMustExist, [FDir + PathDelim + 'nope']), FForm.Problems.Text.Trim);
end;

procedure TFileDialogValidationTest.TestOpenChecksEveryFileOfASelection;
begin
  Touch('a.txt');
  Touch('b.txt');
  Dialog(False, [fdoFileMustExist, fdoAllowMultiSelect]);
  FForm.ShellList.SelectAll;
  AssertEquals('setup: both files are selected', 2, FForm.ShellList.SelCount);
  FForm.NameEdit.Text := 'a.txt';
  DeleteFile(FDir + PathDelim + 'b.txt');   // gone between picking it and pressing OK
  AssertFalse('a selection holding a file that has gone is refused', Accepts);
  AssertEquals('one message', 1, FForm.Problems.Count);
  AssertTrue('naming that file: ' + FForm.Problems.Text, Pos('b.txt', FForm.Problems[0]) > 0);
end;

procedure TFileDialogValidationTest.TestOpenChecksTheTypedNameBesideASelection;
begin
  Touch('a.txt');
  Touch('b.txt');
  Dialog(False, [fdoFileMustExist, fdoAllowMultiSelect]);
  FForm.ShellList.SelectAll;
  FForm.NameEdit.Text := 'c.txt';
  AssertFalse('a typed name that is not there is refused, whatever else is selected', Accepts);
  AssertTrue('naming it: ' + FForm.Problems.Text, Pos('c.txt', FForm.Problems.Text) > 0);
end;

{ The program's OnCanClose (forwarded onto the form's OnCloseQuery) records that it was asked. }
procedure TFileDialogValidationTest.CanClose(Sender: TObject; var ACanClose: Boolean);
begin
  FAsked := True;
  ACanClose := FAnswer;
end;

{ OnCanClose is where a program acts on the choice -- saves, say. It used to be asked first, so
  it could say yes and act, and the validation after it still kept the dialog open. }
procedure TFileDialogValidationTest.TestOnCanCloseIsNotAskedAboutARefusedName;
begin
  Dialog(True, [fdoPathMustExist]);
  FForm.OnCloseQuery := @CanClose;
  FAsked := False;
  FAnswer := True;
  FForm.NameEdit.Text := FDir + PathDelim + 'nope' + PathDelim + 'x.txt';
  AssertFalse('setup: the name is refused', Accepts);
  AssertFalse('and OnCanClose was never asked about it', FAsked);
end;

procedure TFileDialogValidationTest.TestOnCanCloseHasTheLastWord;
begin
  Dialog(True, [fdoPathMustExist]);
  FForm.OnCloseQuery := @CanClose;
  FForm.NameEdit.Text := FDir + PathDelim + 'new.txt';
  FAsked := False;
  FAnswer := False;
  AssertFalse('a name that passes is still the program''s to refuse', Accepts);
  AssertTrue('it was asked', FAsked);
  FAnswer := True;
  AssertTrue('and when it agrees the dialog closes', Accepts);
end;

initialization
  Randomize;
  RegisterTest(TFileDialogResolveTest);
  RegisterTest(TFileDialogValidationTest);
end.
