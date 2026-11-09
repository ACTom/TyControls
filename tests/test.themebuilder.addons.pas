unit test.themebuilder.addons;
{ The theme builder reads add-on stylesheets (tbaddons): from a file, from an addons folder,
  from the command line, and from the File menu. What it knows -- the typeKeys of the coverage
  check, the AI reference's variables, the base variable names -- grows with them, including
  the lists that are built once (they are rebuilt, not read stale). }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, Controls, tyControls.StyleModel, tbmain;

type
  TTbAddOnTests = class(TTestCase)
  private
    FDir: string;
    FModel: TTyStyleModel;     { a live model, as the running tool has }
    procedure WriteFile(const AName, AText: string);
    procedure ForgetAll;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestCoverageKnowsAnAddOnTypeKey;
    procedure TestTheAiReferenceListsAnAddOnToken;
    procedure TestNoAddOnsDirIsQuiet;
    procedure TestTheFileNameIsTheAddOnName;
    procedure TestADirLoadsEveryTycssFile;
    procedure TestABrokenFileRaisesAndLeavesNothing;
    procedure TestABrokenFileInADirDoesNotStopTheOthers;
    procedure TestTheStartUpLoadReadsTheFolderAndTheArguments;
    procedure TestTheStartUpLoadNeverRaises;
    procedure TestTheBaseVariablesIncludeAnAddOnsToken;
    procedure TestTheBaseTypeKeysIncludeAnAddOnsKey;
  end;

  TTbAddOnFormTests = class(TTestCase)
  private
    FDir: string;
    FForm: TTbMainForm;
    function HasUndefinedVar: Boolean;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheMenuItemIsInTheForm;
    procedure TestLoadingAnAddOnClearsTheUndefinedVariable;
    procedure TestABrokenAddOnIsReportedNotRaised;
  end;

implementation

uses
  FileUtil, Forms, Dialogs, tyControls.Controller, tyControls.Css.AddOns, tbaddons, tbcoverage,
  tbproblems, tbreference, tbpreview;

const
  cZzCss = ':root{--zz-gap:7px;} TyZzThing{background:#123456;}';
  { parses, but its rule names a variable nobody defines: the load refuses it }
  cBrokenCss = ':root{--zz-gap:8px;} TyZzThing{background:var(--zz-nowhere);}';
  cNames: array[0..4] of string = ('tbadd.one', 'tbadd.two', 'tbadd.bad', 'tbadd.arg', 'tbadd.eq');

var
  GSeq: Integer = 0;

function MakeDir(const ATag: string): string;
begin
  Inc(GSeq);
  Result := IncludeTrailingPathDelimiter(GetTempDir(False)) +
    Format('tb5-%s-%d-%d', [ATag, GetProcessID, GSeq]) + PathDelim;
  ForceDirectories(Result);
end;

procedure WriteText(const AFileName, AText: string);
var
  sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.Text := AText;
    sl.SaveToFile(AFileName);
  finally
    sl.Free;
  end;
end;

procedure ForgetAddOns(const ANames: array of string);
var
  i: Integer;
begin
  for i := 0 to High(ANames) do
    TyUnregisterAddOnCss(ANames[i]);
  { unregistering tells no listener: the lists built meanwhile are forgotten by hand }
  TbForgetKnownKeys;
  TbForgetPreviewCaches;
  TbForgetReference;
end;

{ ---- TTbAddOnTests ---- }

procedure TTbAddOnTests.SetUp;
begin
  FDir := MakeDir('addon');
  FModel := TTyStyleModel.Create;
end;

procedure TTbAddOnTests.TearDown;
begin
  ForgetAddOns(cNames);
  ForgetAddOns(['zzfile', 'a', 'b', 'zzarg']);
  FModel.Free;
  DeleteDirectory(ExcludeTrailingPathDelimiter(FDir), False);
end;

procedure TTbAddOnTests.WriteFile(const AName, AText: string);
begin
  WriteText(FDir + AName, AText);
end;

procedure TTbAddOnTests.ForgetAll;
begin
  ForgetAddOns(cNames);
end;

function Has(const AArr: TStringArray; const AText: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to High(AArr) do
    if AArr[i] = AText then Exit(True);
end;

{ The list is built first (asked about the key before it exists), then the add-on loads: the
  answer changes. A list built once and never rebuilt answers no both times. }
procedure TTbAddOnTests.TestCoverageKnowsAnAddOnTypeKey;
begin
  AssertFalse('before: not a typeKey of anything', TbIsKnownTypeKey('TyZzThing', nil));
  WriteFile('zzfile.tycss', cZzCss);
  TbLoadAddOnFile(FDir + 'zzfile.tycss');
  AssertTrue('after: the add-on defines it', TbIsKnownTypeKey('TyZzThing', nil));
  AssertTrue('case does not matter', TbIsKnownTypeKey('tyzzthing', nil));
  AssertFalse('a typo of it is still unknown', TbIsKnownTypeKey('TyZzThng', nil));
end;

procedure TTbAddOnTests.TestTheAiReferenceListsAnAddOnToken;
begin
  AssertEquals('before: the reference (built now) does not know it', 0,
    Pos('--zz-gap', TbReferenceText));
  WriteFile('zzfile.tycss', cZzCss);
  TbLoadAddOnFile(FDir + 'zzfile.tycss');
  AssertTrue('after: it is in the reference, which was built before',
    Pos('--zz-gap', TbReferenceText) > 0);
  AssertTrue('and the add-on''s key is a selector it may name',
    Pos('TyZzThing', TbReferenceText) > 0);
end;

procedure TTbAddOnTests.TestNoAddOnsDirIsQuiet;
var
  before: Integer;
begin
  before := Length(TyAddOnNames);
  TbLoadAddOnsDir(FDir + 'nowhere' + PathDelim);
  TbLoadAddOnsDir(FDir + 'nowhere');
  TbLoadAddOnsDir('');
  AssertEquals('nothing was registered', before, Length(TyAddOnNames));
  AssertEquals('and the start-up load finds nothing to say', 0,
    TbLoadStartupAddOns(FDir + 'nowhere', nil, nil));
end;

procedure TTbAddOnTests.TestTheFileNameIsTheAddOnName;
begin
  WriteFile('zzfile.tycss', cZzCss);
  TbLoadAddOnFile(FDir + 'zzfile.tycss');
  AssertTrue('registered under the name without the extension', Has(TyAddOnNames, 'zzfile'));
  AssertEquals('with the file''s text', cZzCss, Trim(TyAddOnCssOf('zzfile')));
  AssertTrue('its token is in the vocabulary', Has(TyCatalogAllTokens, '--zz-gap'));
  AssertTrue('and its typeKey', Has(TyCatalogAllTypeKeys, 'TyZzThing'));
end;

procedure TTbAddOnTests.TestADirLoadsEveryTycssFile;
begin
  WriteFile('a.tycss', ':root{--zz-a:1px;}');
  WriteFile('b.tycss', ':root{--zz-b:2px;} TyZzB{background:#111111;}');
  WriteFile('c.txt', ':root{--zz-c:3px;}');
  TbLoadAddOnsDir(FDir);
  AssertTrue('a', Has(TyAddOnNames, 'a'));
  AssertTrue('b', Has(TyAddOnNames, 'b'));
  AssertFalse('c.txt is not a stylesheet', Has(TyAddOnNames, 'c'));
  AssertTrue('the tokens joined', Has(TyCatalogAllTokens, '--zz-a') and Has(TyCatalogAllTokens, '--zz-b'));
  AssertFalse('c''s did not', Has(TyCatalogAllTokens, '--zz-c'));
end;

procedure TTbAddOnTests.TestABrokenFileRaisesAndLeavesNothing;
var
  raised: Boolean;
  msg: string;
begin
  WriteFile('tbadd.bad.tycss', cBrokenCss);
  raised := False;
  try
    TbLoadAddOnFile(FDir + 'tbadd.bad.tycss');
  except
    on E: Exception do
    begin
      raised := True;
      msg := E.Message;
    end;
  end;
  AssertTrue('raised', raised);
  AssertTrue('and names the add-on: ' + msg, Pos('tbadd.bad', msg) > 0);
  AssertFalse('nothing of it stays registered', Has(TyAddOnNames, 'tbadd.bad'));
  AssertFalse('nor in the vocabulary', Has(TyCatalogAllTokens, '--zz-gap'));
  { and a file that is not there raises too }
  raised := False;
  try
    TbLoadAddOnFile(FDir + 'missing.tycss');
  except
    raised := True;
  end;
  AssertTrue('a missing file raises', raised);
end;

procedure TTbAddOnTests.TestABrokenFileInADirDoesNotStopTheOthers;
var
  raised: Boolean;
  msg: string;
begin
  WriteFile('a.tycss', ':root{--zz-a:1px;}');
  WriteFile('b.tycss', cBrokenCss);
  WriteFile('tbadd.one.tycss', ':root{--zz-one:1px;}');
  raised := False;
  try
    TbLoadAddOnsDir(FDir);
  except
    on E: Exception do
    begin
      raised := True;
      msg := E.Message;
    end;
  end;
  AssertTrue('the folder reports the failure', raised);
  AssertTrue('and names the file: ' + msg, Pos('b.tycss', msg) > 0);
  AssertTrue('the files before it loaded', Has(TyAddOnNames, 'a'));
  AssertTrue('and the ones after', Has(TyAddOnNames, 'tbadd.one'));
  AssertFalse('the broken one did not', Has(TyAddOnNames, 'b'));
end;

procedure TTbAddOnTests.TestTheStartUpLoadReadsTheFolderAndTheArguments;
var
  args, errors: TStringList;
  n: Integer;
begin
  ForceDirectories(FDir + 'addons');
  WriteText(FDir + 'addons' + PathDelim + 'a.tycss', ':root{--zz-a:1px;}');
  WriteFile('zzarg.tycss', ':root{--zz-arg:1px;}');
  WriteFile('tbadd.eq.tycss', ':root{--zz-eq:1px;}');
  args := TStringList.Create;
  errors := TStringList.Create;
  try
    args.Add('--addon');
    args.Add(FDir + 'zzarg.tycss');
    args.Add('--other');
    args.Add('--addon=' + FDir + 'tbadd.eq.tycss');
    n := TbLoadStartupAddOns(ExcludeTrailingPathDelimiter(FDir), args, errors);
    AssertEquals('three files loaded', 3, n);
    AssertEquals('no complaint: ' + errors.Text, 0, errors.Count);
    AssertTrue('the folder''s', Has(TyAddOnNames, 'a'));
    AssertTrue('--addon <file>', Has(TyAddOnNames, 'zzarg'));
    AssertTrue('--addon=<file>', Has(TyAddOnNames, 'tbadd.eq'));
  finally
    errors.Free;
    args.Free;
  end;
end;

procedure TTbAddOnTests.TestTheStartUpLoadNeverRaises;
var
  args, errors: TStringList;
  n: Integer;
begin
  WriteFile('tbadd.bad.tycss', cBrokenCss);
  WriteFile('tbadd.one.tycss', ':root{--zz-one:1px;}');
  args := TStringList.Create;
  errors := TStringList.Create;
  try
    args.Add('--addon');
    args.Add(FDir + 'tbadd.bad.tycss');
    args.Add('--addon');
    args.Add(FDir + 'missing.tycss');
    args.Add('--addon');
    args.Add(FDir + 'tbadd.one.tycss');
    args.Add('--addon');       { a name missing at the end }
    n := TbLoadStartupAddOns('', args, errors);
    AssertEquals('the good one loaded', 1, n);
    AssertEquals('one line each for the broken, the missing and the lone --addon: ' +
      errors.Text, 3, errors.Count);
    AssertTrue('the first names the add-on', Pos('tbadd.bad', errors[0]) > 0);
    AssertTrue('and so does the second its file', Pos('missing.tycss', errors[1]) > 0);
    AssertEquals('without a list to fill it still does not raise', 1,
      TbLoadStartupAddOns('', args, nil));
  finally
    errors.Free;
    args.Free;
  end;
end;

procedure TTbAddOnTests.TestTheBaseVariablesIncludeAnAddOnsToken;
var
  names: TStringList;
begin
  names := TStringList.Create;
  try
    TbBaseVarNames(names);
    AssertTrue('before: not there', names.IndexOf('zz-gap') < 0);
    names.Clear;
    WriteFile('zzfile.tycss', cZzCss);
    TbLoadAddOnFile(FDir + 'zzfile.tycss');
    TbBaseVarNames(names);
    AssertTrue('after: the problem check knows var(--zz-gap)', names.IndexOf('zz-gap') >= 0);
  finally
    names.Free;
  end;
end;

procedure TTbAddOnTests.TestTheBaseTypeKeysIncludeAnAddOnsKey;
var
  keys: TStringList;
begin
  keys := TStringList.Create;
  try
    TbBaseTypeKeys(keys);          { builds the list }
    AssertTrue('before: not there', keys.IndexOf('TyZzThing') < 0);
    keys.Clear;
    WriteFile('zzfile.tycss', cZzCss);
    TbLoadAddOnFile(FDir + 'zzfile.tycss');
    TbBaseTypeKeys(keys);
    AssertTrue('after: a key of the base layer''s rules', keys.IndexOf('TyZzThing') >= 0);
  finally
    keys.Free;
  end;
end;

{ ---- TTbAddOnFormTests ---- }

var
  GWidgetSetReady: Boolean = False;

procedure TTbAddOnFormTests.SetUp;
begin
  if not GWidgetSetReady then
  begin
    Forms.Application.Initialize;
    GWidgetSetReady := True;
  end;
  FDir := MakeDir('form');
  TTbMainForm.SettingsFileForTest := FDir + 'settings' + PathDelim + 'themebuilder.ini';
  TTbMainForm.PromptAnswerForTest := mrOk;
  FForm := TTbMainForm.Create(nil);
end;

procedure TTbAddOnFormTests.TearDown;
begin
  FreeAndNil(FForm);
  TTbMainForm.PromptAnswerForTest := mrNone;
  TTbMainForm.SettingsFileForTest := '';
  ForgetAddOns(['zzfile', 'tbadd.bad']);
  DeleteDirectory(ExcludeTrailingPathDelimiter(FDir), False);
end;

function TTbAddOnFormTests.HasUndefinedVar: Boolean;
var
  i: Integer;
  p: TTbProblems;
begin
  p := FForm.Problems;
  Result := False;
  for i := 0 to High(p) do
    if Pos('zz-gap', p[i].Text) > 0 then Exit(True);
end;

procedure TTbAddOnFormTests.TestTheMenuItemIsInTheForm;
begin
  AssertTrue('the item is in the .lfm', FForm.MnuLoadAddOn <> nil);
  AssertTrue('with its handler', Assigned(FForm.MnuLoadAddOn.OnClick));
  AssertTrue('in the File menu', FForm.MnuLoadAddOn.Parent = FForm.MnuFile);
  AssertTrue('captioned', Pos('add-on', FForm.MnuLoadAddOn.Caption) > 0);
end;

procedure TTbAddOnFormTests.TestLoadingAnAddOnClearsTheUndefinedVariable;
begin
  FForm.Editor.Lines.Text := 'TyZzThing { background: var(--zz-gap); }';
  FForm.RefreshNow;
  AssertTrue('before: var(--zz-gap) is reported', HasUndefinedVar);
  WriteText(FDir + 'zzfile.tycss', cZzCss);
  AssertTrue('loaded', FForm.LoadAddOnFile(FDir + 'zzfile.tycss'));
  AssertFalse('after: the document is checked again and it is a known variable',
    HasUndefinedVar);
end;

procedure TTbAddOnFormTests.TestABrokenAddOnIsReportedNotRaised;
begin
  WriteText(FDir + 'tbadd.bad.tycss', cBrokenCss);
  AssertFalse('not loaded', FForm.LoadAddOnFile(FDir + 'tbadd.bad.tycss'));
  AssertTrue('the person is told', Pos('tbadd.bad', FForm.LastAsk) > 0);
  AssertTrue('as an error', FForm.LastAskType = mtError);
  AssertFalse('nothing registered', Has(TyAddOnNames, 'tbadd.bad'));
end;

initialization
  RegisterTest(TTbAddOnTests);
  RegisterTest(TTbAddOnFormTests);
end.
