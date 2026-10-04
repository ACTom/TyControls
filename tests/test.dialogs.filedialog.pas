unit test.dialogs.filedialog;
{ (#28 added three suites at the end of this unit: the 3.0 option names still loading, the
  pure TyFileDialogCheck, and the component's BuildForm / ApplyResult -- the form CAN be built
  headless; only ShowModal and the message boxes cannot run here.)

  Headless tests for the pure resolver of the phase-7 file dialogs:

    function TyFileDialogResolveName(ASaveMode: Boolean;
      const ADir, ATyped, ASelected, ADefaultExt: string): string;

  Every rule from the phase-7 plan's "pure resolver function" section is pinned against the
  pure function alone.

  Semantics under test (plan lines):
    Save  : bare name expands against ADir + ADefaultExt appended when the
            resolved name has no extension (== TyFsResolveSaveName, cross-checked).
    Open  : a NON-EMPTY typed name always wins (directory-bearing verbatim, else a
            bare name expanded against ADir) -- it is what the user edits in the name
            box; only an EMPTY box falls back to ASelected (the focused item); all
            empty -> ''. }

{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Forms, Controls, Dialogs, LazFileUtils, fpcunit, testregistry,
  tyControls.FileSystem, tyControls.Dialogs.FileDialog, tyControls.ListView,
  tyControls.ShellListView, tyControls.Button, tyControls.StrConsts;
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

  { Options became LCL's TOpenOptions (#28); 3.0's names must still load. }
  TFileDialogLegacyOptionsTest = class(TTestCase)
  private
    function Load(const AOptions: string): TOpenOptions;
  published
    procedure TestEachOldNameLoadsAsItsLclValue;
    procedure TestOldNamesMixWithNew;
    procedure TestFormsWriteTheLclNames;
    procedure TestTheDefaultStaysEmptyAndUnwritten;
    procedure TestOldConstantsAreTheLclValues;
  end;

  { TyFileDialogCheck: what OK may do with one chosen file. }
  TFileDialogCheckTest = class(TTestCase)
  private
    FDir, FFile, FReadOnly: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestNoOptionsAcceptsAnything;
    procedure TestPathMustExist;
    procedure TestFileMustExistBothModes;
    procedure TestNoReadOnlyReturn;
    procedure TestCreatePrompt;
    procedure TestOverwritePromptOnlyWhenSaving;
    procedure TestOrder;
  end;

  { BuildForm and ApplyResult: the two halves of Execute around ShowModal. }
  TFileDialogComponentTest = class(TTestCase)
  private
    FHelpSender: TObject;
    procedure HandleHelp(Sender: TObject);
    function ListOf(AForm: TTyFileDialogForm): TTyShellListView;
    function HelpOf(AForm: TTyFileDialogForm): TTyButton;
  published
    procedure TestExtensionDifferent;
    procedure TestExtensionDifferentIsClearedFirst;
    procedure TestNoChangeDir;
    procedure TestCancelChangesNothing;
    procedure TestForceShowHiddenAndMultiSelectReachTheList;
    procedure TestShowHelp;
  end;

  { The form with its error box swapped for a list, so a refused name can be read instead of
    putting a modal window up. Everything else is the real form: the name box, the list, the
    OK path through CloseQuery. }
  TProbeFileDialog = class(TTyFileDialogForm)
  protected
    procedure ReportProblem(const AMsg: string); override;
    function ConfirmChoice(const AMsg: string): Boolean; override;
  public
    Problems: TStringList;
    Questions: TStringList;   // every yes / no question, in order
    Answer: Boolean;          // what the user answers to each
  end;

  { ofPathMustExist and ofFileMustExist as LCL's TOpenDialog.CheckFile / CheckAllFiles apply
    them, through the real OK path: for an open AND a save, the folder before the file, and
    for every file of a multiple selection. 3.0.0 never looked at fdoPathMustExist, checked
    fdoFileMustExist for an open only, and for a selection checked one name. }
  TFileDialogValidationTest = class(TTestCase)
  private
    FDir: string;
    FForm: TProbeFileDialog;
    FAsked: Boolean;
    FAnswer: Boolean;
    procedure CanClose(Sender: TObject; var ACanClose: Boolean);
    procedure Touch(const AName: string);
    procedure Dialog(ASave: Boolean; AOptions: TOpenOptions);
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
    procedure TestCreatePromptAsksAndTheAnswerDecides;
    procedure TestOverwritePromptAsksOnlyForAnExistingFileOnSave;
    procedure TestTheTypedNameInTheSelectionIsAskedOnce;
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

{ TFileDialogLegacyOptionsTest }

function TFileDialogLegacyOptionsTest.Load(const AOptions: string): TOpenOptions;
var f: TForm; ts: TStringStream; bs: TMemoryStream;
begin
  f := TForm.CreateNew(nil);
  ts := TStringStream.Create(
    'object Form1: TForm' + LineEnding +
    '  object D: TTyOpenDialog' + LineEnding +
    '    Options = ' + AOptions + LineEnding +
    '  end' + LineEnding +
    'end' + LineEnding);
  bs := TMemoryStream.Create;
  try
    ObjectTextToBinary(ts, bs);
    bs.Position := 0;
    bs.ReadComponent(f);
    Result := (f.FindComponent('D') as TTyOpenDialog).Options;
  finally
    bs.Free; ts.Free; f.Free;
  end;
end;

procedure TFileDialogLegacyOptionsTest.TestEachOldNameLoadsAsItsLclValue;
begin
  AssertTrue('fdoOverwritePrompt', Load('[fdoOverwritePrompt]') = [ofOverwritePrompt]);
  AssertTrue('fdoFileMustExist', Load('[fdoFileMustExist]') = [ofFileMustExist]);
  AssertTrue('fdoPathMustExist', Load('[fdoPathMustExist]') = [ofPathMustExist]);
  AssertTrue('fdoAllowMultiSelect', Load('[fdoAllowMultiSelect]') = [ofAllowMultiSelect]);
end;

procedure TFileDialogLegacyOptionsTest.TestOldNamesMixWithNew;
begin
  AssertTrue('a 3.0 form: all four',
    Load('[fdoOverwritePrompt, fdoFileMustExist, fdoPathMustExist, fdoAllowMultiSelect]')
    = [ofOverwritePrompt, ofFileMustExist, ofPathMustExist, ofAllowMultiSelect]);
  AssertTrue('an LCL form', Load('[ofEnableSizing, ofViewDetail, ofShowHelp]')
    = [ofEnableSizing, ofViewDetail, ofShowHelp]);
end;

procedure TFileDialogLegacyOptionsTest.TestFormsWriteTheLclNames;
var src: TForm; d: TTySaveDialog; ms, ts: TMemoryStream; L: TStringList;
begin
  src := TForm.CreateNew(nil);
  ms := TMemoryStream.Create;
  ts := TMemoryStream.Create;
  L := TStringList.Create;
  try
    d := TTySaveDialog.Create(src);
    d.Name := 'D';
    d.Options := [ofOverwritePrompt, ofPathMustExist];
    ms.WriteComponent(src);
    ms.Position := 0;
    ObjectBinaryToText(ms, ts);
    ts.Position := 0;
    L.LoadFromStream(ts);
    AssertTrue('written with LCL''s names' + LineEnding + L.Text,
      Pos('Options = [ofOverwritePrompt, ofPathMustExist]', L.Text) > 0);
    AssertEquals('never the old ones', 0, Pos('fdo', L.Text));
  finally
    L.Free; ts.Free; ms.Free; src.Free;
  end;
end;

procedure TFileDialogLegacyOptionsTest.TestTheDefaultStaysEmptyAndUnwritten;
var src: TForm; d: TTyOpenDialog; ms, ts: TMemoryStream; L: TStringList;
begin
  src := TForm.CreateNew(nil);
  ms := TMemoryStream.Create;
  ts := TMemoryStream.Create;
  L := TStringList.Create;
  try
    d := TTyOpenDialog.Create(src);
    d.Name := 'D';
    AssertTrue('default [] (not LCL''s [ofEnableSizing, ofViewDetail])', d.Options = []);
    ms.WriteComponent(src);
    ms.Position := 0;
    ObjectBinaryToText(ms, ts);
    ts.Position := 0;
    L.LoadFromStream(ts);
    AssertEquals('not written', 0, Pos('Options', L.Text));
    AssertEquals('OnHelpClicked unset is not written', 0, Pos('OnHelpClicked', L.Text));
  finally
    L.Free; ts.Free; ms.Free; src.Free;
  end;
end;

{$push}{$warn 5043 off}{$warn 5066 off}   // the deprecated 3.0 names are what is under test
procedure TFileDialogLegacyOptionsTest.TestOldConstantsAreTheLclValues;
var o: TTyFileDialogOptions;
begin
  AssertTrue('fdoOverwritePrompt', fdoOverwritePrompt = ofOverwritePrompt);
  AssertTrue('fdoFileMustExist', fdoFileMustExist = ofFileMustExist);
  AssertTrue('fdoPathMustExist', fdoPathMustExist = ofPathMustExist);
  AssertTrue('fdoAllowMultiSelect', fdoAllowMultiSelect = ofAllowMultiSelect);
  o := [fdoAllowMultiSelect];
  AssertTrue('3.0 code still builds a set', o = [ofAllowMultiSelect]);
end;
{$pop}

{ TFileDialogCheckTest }

procedure TFileDialogCheckTest.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir)
        + Format('tyfdcheck_%d_%d', [PtrUInt(Self), Random(MaxInt)]);
  ForceDirectories(FDir);
  FFile := FDir + PathDelim + 'a.txt';
  FReadOnly := FDir + PathDelim + 'ro.txt';
  with TStringList.Create do
    try
      Add('x');
      SaveToFile(FFile);
      SaveToFile(FReadOnly);
    finally Free; end;
  FileSetAttr(FReadOnly, faReadOnly);
end;

procedure TFileDialogCheckTest.TearDown;
begin
  FileSetAttr(FReadOnly, 0);
  DeleteFile(FReadOnly);
  DeleteFile(FFile);
  RemoveDir(FDir);
end;

procedure TFileDialogCheckTest.TestNoOptionsAcceptsAnything;
begin
  AssertTrue('existing', TyFileDialogCheck(False, FFile, []) = fdcOK);
  AssertTrue('missing', TyFileDialogCheck(False, FDir + PathDelim + 'none.txt', []) = fdcOK);
  AssertTrue('missing folder', TyFileDialogCheck(True,
    FDir + PathDelim + 'nodir' + PathDelim + 'x.txt', []) = fdcOK);
  AssertTrue('existing, saving', TyFileDialogCheck(True, FFile, []) = fdcOK);
end;

procedure TFileDialogCheckTest.TestPathMustExist;
begin
  AssertTrue('its folder is missing', TyFileDialogCheck(True,
    FDir + PathDelim + 'nodir' + PathDelim + 'x.txt', [ofPathMustExist]) = fdcPathMissing);
  AssertTrue('its folder exists, the file need not', TyFileDialogCheck(True,
    FDir + PathDelim + 'new.txt', [ofPathMustExist]) = fdcOK);
end;

procedure TFileDialogCheckTest.TestFileMustExistBothModes;
begin
  AssertTrue('missing, open', TyFileDialogCheck(False,
    FDir + PathDelim + 'none.txt', [ofFileMustExist]) = fdcFileMissing);
  AssertTrue('missing, save (LCL checks both)', TyFileDialogCheck(True,
    FDir + PathDelim + 'none.txt', [ofFileMustExist]) = fdcFileMissing);
  AssertTrue('existing', TyFileDialogCheck(False, FFile, [ofFileMustExist]) = fdcOK);
end;

procedure TFileDialogCheckTest.TestNoReadOnlyReturn;
begin
  if FileIsWritable(FReadOnly) then Ignore('this file system has no read-only attribute');
  AssertTrue('a read-only file', TyFileDialogCheck(False, FReadOnly,
    [ofNoReadOnlyReturn]) = fdcNotWritable);
  AssertTrue('a writable one', TyFileDialogCheck(False, FFile, [ofNoReadOnlyReturn]) = fdcOK);
  AssertTrue('a new one in a writable folder', TyFileDialogCheck(True,
    FDir + PathDelim + 'new.txt', [ofNoReadOnlyReturn]) = fdcOK);
  AssertTrue('without the option a read-only file is fine',
    TyFileDialogCheck(False, FReadOnly, []) = fdcOK);
end;

procedure TFileDialogCheckTest.TestCreatePrompt;
begin
  AssertTrue('missing -> ask', TyFileDialogCheck(False,
    FDir + PathDelim + 'none.txt', [ofCreatePrompt]) = fdcAskCreate);
  AssertTrue('missing, saving -> ask', TyFileDialogCheck(True,
    FDir + PathDelim + 'none.txt', [ofCreatePrompt]) = fdcAskCreate);
  AssertTrue('existing -> nothing to create', TyFileDialogCheck(False, FFile,
    [ofCreatePrompt]) = fdcOK);
end;

procedure TFileDialogCheckTest.TestOverwritePromptOnlyWhenSaving;
begin
  AssertTrue('saving over a file -> ask', TyFileDialogCheck(True, FFile,
    [ofOverwritePrompt]) = fdcAskOverwrite);
  AssertTrue('opening it -> nothing to overwrite', TyFileDialogCheck(False, FFile,
    [ofOverwritePrompt]) = fdcOK);
  AssertTrue('saving a new file', TyFileDialogCheck(True, FDir + PathDelim + 'new.txt',
    [ofOverwritePrompt]) = fdcOK);
end;

procedure TFileDialogCheckTest.TestOrder;
begin
  AssertTrue('the folder before the file', TyFileDialogCheck(False,
    FDir + PathDelim + 'nodir' + PathDelim + 'x.txt',
    [ofPathMustExist, ofFileMustExist]) = fdcPathMissing);
  AssertTrue('must exist beats offering to create', TyFileDialogCheck(False,
    FDir + PathDelim + 'none.txt', [ofFileMustExist, ofCreatePrompt]) = fdcFileMissing);
  if not FileIsWritable(FReadOnly) then
    AssertTrue('read-only beats the overwrite question', TyFileDialogCheck(True, FReadOnly,
      [ofNoReadOnlyReturn, ofOverwritePrompt]) = fdcNotWritable);
end;

{ TFileDialogComponentTest }

procedure TFileDialogComponentTest.HandleHelp(Sender: TObject);
begin
  FHelpSender := Sender;
end;

function TFileDialogComponentTest.ListOf(AForm: TTyFileDialogForm): TTyShellListView;
var i: Integer;
begin
  for i := 0 to AForm.ComponentCount - 1 do
    if AForm.Components[i] is TTyShellListView then
      Exit(TTyShellListView(AForm.Components[i]));
  Fail('no file list on the form');
  Result := nil;
end;

function TFileDialogComponentTest.HelpOf(AForm: TTyFileDialogForm): TTyButton;
var i: Integer;
begin
  Result := nil;
  for i := 0 to AForm.ButtonCount - 1 do
    if AForm.Buttons[i].Caption = rsMsgBtnHelp then Exit(AForm.Buttons[i]);
end;

procedure TFileDialogComponentTest.TestExtensionDifferent;
var d: TTySaveDialog; two: TStringList;
begin
  d := TTySaveDialog.Create(nil);
  two := TStringList.Create;
  try
    d.Options := [ofNoChangeDir];
    d.DefaultExt := 'txt';
    d.ApplyResult(True, 'C:\x\a.md', nil);
    AssertTrue('a.md against txt -> set', ofExtensionDifferent in d.Options);
    d.ApplyResult(True, 'C:\x\a.txt', nil);
    AssertFalse('a.txt -> clear', ofExtensionDifferent in d.Options);
    d.DefaultExt := '.txt';
    d.ApplyResult(True, 'C:\x\a.TXT', nil);
    AssertFalse('a dotted DefaultExt, file names compared as file names',
      ofExtensionDifferent in d.Options);
    two.Add('C:\x\a.md');
    two.Add('C:\x\b.md');
    d.ApplyResult(True, 'C:\x\a.md', two);
    AssertFalse('several files -> never set', ofExtensionDifferent in d.Options);
    d.DefaultExt := '';
    d.ApplyResult(True, 'C:\x\a.md', nil);
    AssertFalse('no DefaultExt -> never set', ofExtensionDifferent in d.Options);
  finally two.Free; d.Free; end;
end;

procedure TFileDialogComponentTest.TestExtensionDifferentIsClearedFirst;
var d: TTySaveDialog;
begin
  d := TTySaveDialog.Create(nil);
  try
    d.DefaultExt := 'txt';
    d.Options := [ofNoChangeDir, ofExtensionDifferent];   // left over from a previous run
    d.ApplyResult(False, '', nil);
    AssertFalse('an output bit: even a cancelled run clears it', ofExtensionDifferent in d.Options);
  finally d.Free; end;
end;

procedure TFileDialogComponentTest.TestNoChangeDir;
var d: TTyOpenDialog;
begin
  d := TTyOpenDialog.Create(nil);
  try
    d.InitialDir := 'C:\start\';
    d.ApplyResult(True, 'C:\picked\a.txt', nil);
    AssertEquals('without ofNoChangeDir InitialDir follows the result',
      'C:\picked\', d.InitialDir);
    AssertEquals('FileName', 'C:\picked\a.txt', d.FileName);
    d.InitialDir := 'C:\start\';
    d.Options := [ofNoChangeDir];
    d.ApplyResult(True, 'C:\other\b.txt', nil);
    AssertEquals('with it InitialDir stays', 'C:\start\', d.InitialDir);
  finally d.Free; end;
end;

procedure TFileDialogComponentTest.TestCancelChangesNothing;
var d: TTyOpenDialog;
begin
  d := TTyOpenDialog.Create(nil);
  try
    d.InitialDir := 'C:\start\';
    d.FileName := 'C:\seed\s.txt';
    d.ApplyResult(False, 'C:\picked\a.txt', nil);
    AssertEquals('FileName', 'C:\seed\s.txt', d.FileName);
    AssertEquals('InitialDir', 'C:\start\', d.InitialDir);
  finally d.Free; end;
end;

procedure TFileDialogComponentTest.TestForceShowHiddenAndMultiSelectReachTheList;
var d: TTyOpenDialog; f: TTyFileDialogForm;
begin
  d := TTyOpenDialog.Create(nil);
  try
    f := d.BuildForm;
    try
      AssertFalse('hidden files stay hidden by default', ListOf(f).ShowHidden);
      AssertFalse('single selection by default', ListOf(f).MultiSelect);
    finally f.Free; end;
    d.Options := [ofForceShowHidden, ofAllowMultiSelect];
    f := d.BuildForm;
    try
      AssertTrue('ofForceShowHidden', ListOf(f).ShowHidden);
      AssertTrue('ofAllowMultiSelect', ListOf(f).MultiSelect);
    finally f.Free; end;
  finally d.Free; end;
end;

procedure TFileDialogComponentTest.TestShowHelp;
var d: TTySaveDialog; f: TTyFileDialogForm;
begin
  FHelpSender := nil;
  d := TTySaveDialog.Create(nil);
  try
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

{ TProbeFileDialog / TFileDialogValidationTest }

procedure TProbeFileDialog.ReportProblem(const AMsg: string);
begin
  Problems.Add(AMsg);
end;

function TProbeFileDialog.ConfirmChoice(const AMsg: string): Boolean;
begin
  Questions.Add(AMsg);
  Result := Answer;
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
    FForm.Questions.Free;
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

procedure TFileDialogValidationTest.Dialog(ASave: Boolean; AOptions: TOpenOptions);
begin
  FForm := TProbeFileDialog.CreateNew(nil);
  FForm.Problems := TStringList.Create;
  FForm.Questions := TStringList.Create;
  FForm.SaveMode := ASave;
  FForm.Options := AOptions;
  FForm.InitialDir := FDir;
end;

{ What pressing OK does: CloseQuery with mrOK, which runs the validation. }
function TFileDialogValidationTest.Accepts: Boolean;
begin
  FForm.Problems.Clear;
  FForm.Questions.Clear;
  FForm.ModalResult := mrOK;
  Result := FForm.CloseQuery;
end;

procedure TFileDialogValidationTest.TestSaveRefusesAFolderThatIsNotThere;
begin
  Dialog(True, [ofPathMustExist]);
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
  Dialog(True, [ofFileMustExist]);
  FForm.NameEdit.Text := 'missing.txt';
  AssertFalse('ofFileMustExist holds for a save too, as in LCL', Accepts);
  AssertEquals('one message', 1, FForm.Problems.Count);
  AssertTrue('naming the file: ' + FForm.Problems.Text, Pos('missing.txt', FForm.Problems[0]) > 0);
  FForm.NameEdit.Text := 'a.txt';
  AssertTrue('an existing file passes', Accepts);
end;

procedure TFileDialogValidationTest.TestOpenRefusesAFolderThatIsNotThere;
begin
  Dialog(False, [ofPathMustExist]);
  FForm.NameEdit.Text := FDir + PathDelim + 'nope' + PathDelim + 'x.txt';
  AssertFalse('an open from a folder that is not there is refused', Accepts);
  AssertEquals('and the message is about the folder, not the file',
    Format(rsFdPathMustExist, [FDir + PathDelim + 'nope']), FForm.Problems.Text.Trim);
end;

procedure TFileDialogValidationTest.TestOpenChecksEveryFileOfASelection;
begin
  Touch('a.txt');
  Touch('b.txt');
  Dialog(False, [ofFileMustExist, ofAllowMultiSelect]);
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
  Dialog(False, [ofFileMustExist, ofAllowMultiSelect]);
  FForm.ShellList.SelectAll;
  FForm.NameEdit.Text := 'c.txt';
  AssertFalse('a typed name that is not there is refused, whatever else is selected', Accepts);
  AssertTrue('naming it: ' + FForm.Problems.Text, Pos('c.txt', FForm.Problems.Text) > 0);
end;

procedure TFileDialogValidationTest.TestCreatePromptAsksAndTheAnswerDecides;
begin
  Dialog(False, [ofCreatePrompt]);
  FForm.NameEdit.Text := 'new.txt';
  FForm.Answer := False;
  AssertFalse('"no": the dialog stays open', Accepts);
  AssertEquals('one question', 1, FForm.Questions.Count);
  AssertEquals('about creating that file',
    Format(rsFdCreatePrompt, [FDir + PathDelim + 'new.txt']), FForm.Questions[0]);
  FForm.Answer := True;
  AssertTrue('"yes": it goes through', Accepts);
  Touch('there.txt');
  FForm.NameEdit.Text := 'there.txt';
  AssertTrue('a file that exists', Accepts);
  AssertEquals('is not asked about', 0, FForm.Questions.Count);
end;

procedure TFileDialogValidationTest.TestOverwritePromptAsksOnlyForAnExistingFileOnSave;
begin
  Touch('a.txt');
  Dialog(True, [ofOverwritePrompt]);
  FForm.NameEdit.Text := 'a.txt';
  FForm.Answer := False;
  AssertFalse('"no": not overwritten', Accepts);
  AssertEquals('asked about replacing it',
    Format(rsFdOverwritePrompt, [FDir + PathDelim + 'a.txt']), FForm.Questions.Text.Trim);
  FForm.Answer := True;
  AssertTrue('"yes": it goes through', Accepts);
  FForm.NameEdit.Text := 'b.txt';
  AssertTrue('a new name', Accepts);
  AssertEquals('is not asked about', 0, FForm.Questions.Count);
end;

procedure TFileDialogValidationTest.TestTheTypedNameInTheSelectionIsAskedOnce;
begin
  { LCL's CheckAllFiles checks the typed name, then each file of the selection -- and not the
    typed name a second time when it is one of them. A question shows that: twice would ask
    the user the same thing twice. }
  Touch('a.txt');
  Touch('b.txt');
  Dialog(False, [ofCreatePrompt, ofAllowMultiSelect]);
  FForm.ShellList.SelectAll;
  AssertEquals('setup: both files are selected', 2, FForm.ShellList.SelCount);
  FForm.NameEdit.Text := 'b.txt';
  DeleteFile(FDir + PathDelim + 'b.txt');   // gone between picking it and pressing OK
  FForm.Answer := True;
  AssertTrue('"yes, create it" lets it through', Accepts);
  AssertEquals('asked once about b.txt, not twice: ' + FForm.Questions.Text, 1,
    FForm.Questions.Count);
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
  Dialog(True, [ofPathMustExist]);
  FForm.OnCloseQuery := @CanClose;
  FAsked := False;
  FAnswer := True;
  FForm.NameEdit.Text := FDir + PathDelim + 'nope' + PathDelim + 'x.txt';
  AssertFalse('setup: the name is refused', Accepts);
  AssertFalse('and OnCanClose was never asked about it', FAsked);
end;

procedure TFileDialogValidationTest.TestOnCanCloseHasTheLastWord;
begin
  Dialog(True, [ofPathMustExist]);
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
  RegisterTest(TFileDialogLegacyOptionsTest);
  RegisterTest(TFileDialogCheckTest);
  RegisterTest(TFileDialogComponentTest);
  RegisterTest(TFileDialogResolveTest);
  RegisterTest(TFileDialogValidationTest);
end.
