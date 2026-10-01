unit test.themebuilder.main;
{ The theme builder's main window (phases 1, 2 and 3), built for real and never shown (as the
  terminal example's tests do). Every question it asks is answered by PromptAnswerForTest, Save As
  takes SaveAsNameForTest and the settings go to a file in a temporary folder -- no test
  path shows a window or touches the user's configuration. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, Controls, Dialogs, tyControls.Controller, tbmain,
  tbaitesthelp;

type
  TTbMainFormTests = class(TTestCase)
  private
    FDir: string;
    FForm: TTbMainForm;
    FThemeName, FMode: string;
    FDensity: TTyDensity;
    FHeard: Integer;
    FModals: Integer;
    procedure Heard(Sender: TObject);
    procedure WriteBytes(const AFileName, ABytes: string);
    function ReadBytes(const AFileName: string): string;
    function Unify(const S: string): string;
    function PreviewButtonBg: Integer;
    function ScriptedAi: TScriptedBackend;
    procedure ModalAccept(Sender: TObject);
    procedure ModalDiscard(Sender: TObject);
    procedure ModalLeave(Sender: TObject);
    procedure ModalOllama(Sender: TObject);
    function PreviewPrimaryBg: Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheWindowIsBuilt;
    procedure TestTypingRefreshes;
    procedure TestAProblemIsMarkedAndJumpedTo;
    procedure TestAParseErrorKeepsThePreview;
    procedure TestSaveKeepsTheBytes;
    procedure TestSaveAsForANewDocument;
    procedure TestSavingABuiltinThemeHints;
    procedure TestClosingAsks;
    procedure TestNewFromABuiltinTheme;
    procedure TestThePreviewCannotTouchTheTool;
    procedure TestTheProjectListsItsUnits;
    procedure TestAnOutsideChangeIsOfferedOnce;
    procedure TestTheReloadQuestionWarnsOfUnsavedChanges;
    procedure TestOurOwnSaveIsNotAnOutsideChange;
    procedure TestTheEditorFollowsTheToolTheme;
    procedure TestTheListenerIsRemoved;
    procedure TestTheSettingsAreKept;
    procedure TestProblemLinesTakeTheirColourFromTheTheme;
    procedure TestTheCatalogueCoversTheForms;
    procedure TestTheCatalogueEntriesAreWhole;
    procedure TestTheTranslationsCoverTheCode;
    procedure TestTheLibraryCatalogueIsACopy;
    procedure TestAVariableCycleIsAProblem;
    procedure TestARefusedDarkReachesTheProblemList;
    procedure TestAFailedSaveLeavesTheFile;
    procedure TestAReadOnlySettingsFileDoesNotKeepTheWindowOpen;
    procedure TestAnErrorAtTheEndIsOnTheLastLine;
    procedure TestAFileThatCannotBeReadStaysRecent;
    procedure TestAnAmpersandInARecentPathIsShown;
    procedure TestTheSideBarShowsItsHints;
    procedure TestTheMarksDoNotTakeTheBookmarkImages;
    procedure TestAFailureIsAnErrorNotAQuestion;
    procedure TestTrailingSpacesOfAnEditedLineAreKept;
    { phase 2 }
    procedure TestTheSeedsPageIsBuilt;
    procedure TestASeedChangeIsOneUndoStep;
    procedure TestEditsOnAnotherTextAreRefused;
    procedure TestTheSeedsFollowTheText;
    procedure TestCtrlClickGoesToTheRule;
    procedure TestCtrlClickAddsARule;
    procedure TestTheCoverageCheckReadsTheDocument;
    procedure TestTheExportTakesTheSavedBytes;
    procedure TestTheSnippetsNameTheFile;
    procedure TestTheViewMenuShowsTheSidePages;
    procedure TestAWindowGoesWithItsHooks;
    procedure TestHowLongARefreshTakes;
    { phase 2, after the review }
    procedure TestAnEmptyEditorGetsNoExtraLine;
    procedure TestCtrlClickKeepsTheLook;
    procedure TestCtrlClickOnAVariantTakesNothingAway;
    procedure TestTheBaseRulesGoBeforeTheDocumentsOwn;
    procedure TestAnImportedPlainRuleIsNotCopiedOver;
    procedure TestTheCoverageCheckGoesToAnyRuleOfTheType;
    procedure TestASplitKeepsTheModernRadius;
    procedure TestTheSeedsPageWaitsTillItIsShown;
    procedure TestRadiusStepsAreOneUndoStep;
    procedure TestAWaitingRadiusIsSaved;
    procedure TestALongNoteTakesASecondLine;
    { phase 3 }
    procedure TestTheAiPageIsBuilt;              { M1 }
    procedure TestGenerateCompareAcceptUndo;     { M2 }
    procedure TestAcceptingKeepsTheCaret;        { M3 }
    procedure TestEditedSinceAsksFirst;          { M4 }
    procedure TestATrialSurvivesARefresh;        { M5 }
    procedure TestANewDocumentStartsAfresh;      { M6 }
    procedure TestTheProblemsBoxFollows;         { M7 }
    procedure TestDiscardChangesNothing;         { M8 }
    procedure TestTheSettingsWindowIsWired;      { M9 }
    procedure TestStopIsWired;                   { M10 }
    procedure TestClosingWhileGenerating;        { M11 }
    procedure TestTheAnswerStreamsIn;            { M12 }
  end;

implementation

uses
  Forms, FileUtil, IniFiles, Graphics, Types, fpjson, jsonparser, SynEdit, SynEditKeyCmds, SynHighlighterCss, SynEditMiscClasses, tyControls.Base,
  tyControls.ThemeLint, tbproblems, tbtemplates, tbeditorlook, tbpreview, tbdocument, test.themebuilder.golden,
  LMessages, LCLType, tbcssscan, tbseeds, tbseedsframe, tbcoverageform, tbexportform, tbsnippetsform,
  tyControls.Types, tyControls.StyleModel, tyControls.DefaultTheme, tyControls.TyLabel, tbthemesource, tbrules,
  tbaiformat, tbaiclient, tbaisettings, tbaisession, tbaiframe, tbcompareform, tbaisettingsform,
  tbdiff;

const
  { a document whose one value no base theme has }
  cMarkerDocMain = 'TyButton { background: #123456; }';

type
  TTyCustomControlAccess = class(TTyCustomControl);

var
  GMainSeq: Integer = 0;

{ TSynCompletion builds its popup form when it is created, and that needs the widgetset
  (the tool and the IDE always have one; this console runner does not until asked). Asked
  once, the first time a test here needs it -- these suites run after the rest. }
var
  GWidgetSetReady: Boolean = False;

procedure NeedWidgetSet;
begin
  if GWidgetSetReady then Exit;
  Forms.Application.Initialize;
  GWidgetSetReady := True;
end;

procedure TTbMainFormTests.SetUp;
begin
  NeedWidgetSet;
  Inc(GMainSeq);
  FDir := IncludeTrailingPathDelimiter(GetTempDir(False)) +
    Format('tb1-main-%d-%d', [GetProcessID, GMainSeq]) + PathDelim;
  ForceDirectories(FDir);
  FThemeName := TyDefaultController.ThemeName;
  FMode := TyDefaultController.Mode;
  FDensity := TyDefaultController.Density;
  TTbMainForm.SettingsFileForTest := FDir + 'settings' + PathDelim + 'themebuilder.ini';
  TTbMainForm.PromptAnswerForTest := mrNo;
  TTbMainForm.SaveAsNameForTest := '';
  TTbMainForm.ShowModalForTest := nil;
  FModals := 0;
  FForm := TTbMainForm.Create(nil);
end;

procedure TTbMainFormTests.TearDown;
begin
  FreeAndNil(FForm);
  TTbMainForm.ShowModalForTest := nil;
  TTbMainForm.SaveAsNameForTest := '';
  TTbMainForm.PromptAnswerForTest := mrNone;
  TTbMainForm.SettingsFileForTest := '';
  if TyDefaultController.ThemeName <> FThemeName then
    TyDefaultController.ThemeName := FThemeName;
  if TyDefaultController.Mode <> FMode then
    TyDefaultController.Mode := FMode;
  if TyDefaultController.Density <> FDensity then
    TyDefaultController.Density := FDensity;
  if DirectoryExists(FDir) then
    DeleteDirectory(ExcludeTrailingPathDelimiter(FDir), False);
end;

procedure TTbMainFormTests.WriteBytes(const AFileName, ABytes: string);
var
  fs: TFileStream;
begin
  ForceDirectories(ExtractFileDir(AFileName));
  fs := TFileStream.Create(AFileName, fmCreate);
  try
    if ABytes <> '' then
      fs.WriteBuffer(ABytes[1], Length(ABytes));
  finally
    fs.Free;
  end;
end;

function TTbMainFormTests.ReadBytes(const AFileName: string): string;
var
  fs: TFileStream;
begin
  Result := '';
  fs := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, fs.Size);
    if fs.Size > 0 then
      fs.ReadBuffer(Result[1], fs.Size);
  finally
    fs.Free;
  end;
end;

{ LF line breaks and no trailing ones: SynEdit's Lines.Text ends with a break }
function TTbMainFormTests.Unify(const S: string): string;
begin
  Result := StringReplace(S, #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #13, #10, [rfReplaceAll]);
  while (Result <> '') and (Result[Length(Result)] = #10) do
    SetLength(Result, Length(Result) - 1);
end;

function TTbMainFormTests.PreviewButtonBg: Integer;
begin
  Result := Integer(Cardinal(FForm.Preview.Controller.Model.ResolveStyle('TyButton', '', [])
    .Background.Color) and $FFFFFF);
end;

procedure TTbMainFormTests.TestTheWindowIsBuilt;
begin
  AssertEquals('F1: three side windows', 3, FForm.SideBar.WindowCount);
  AssertTrue('F1: the seeds first', FForm.SideBar.Windows[0] = FForm.SeedsWin);
  AssertTrue('F1: the problems', FForm.SideBar.Windows[1] = FForm.ProblemsWin);
  AssertTrue('F1: the AI page', FForm.SideBar.Windows[2] = FForm.AiWin);
  AssertTrue('F1: the kit is attached', FForm.Editor.Highlighter is TSynCssSyn);
  AssertTrue('F1: the kit is the form''s', FForm.Kit.Edit = FForm.Editor);
  AssertFalse('F1: no tidying of the line left', FForm.Kit.FormatOnLineLeave);
  AssertTrue('F1: the preview is in its host', FForm.Preview.Parent = FForm.PreviewHost);
  AssertTrue('F1: a real title bar', FForm.TitleBar = FForm.Bar);
  AssertTrue('F1: untitled: ' + FForm.Bar.Caption, Pos('Untitled', FForm.Bar.Caption) > 0);
  AssertEquals('F1: the minimal template', Unify(TbMinimalTemplate), Unify(FForm.Editor.Lines.Text));
  AssertEquals('F1: no errors', 0, TbErrorCount(FForm.Problems));
end;

procedure TTbMainFormTests.TestTypingRefreshes;
begin
  FForm.RefreshTimer.Enabled := False;
  FForm.Editor.Lines.Text := cMarkerDocMain;
  if not FForm.RefreshTimer.Enabled then
    FForm.Editor.OnChange(FForm.Editor);   { headless SynEdit may not fire it: call the chain }
  AssertTrue('F2: typing starts the timer', FForm.RefreshTimer.Enabled);
  FForm.RefreshNow;
  AssertFalse('F2: refreshing stops it', FForm.RefreshTimer.Enabled);
  AssertEquals('F2: the preview has the text', $123456, PreviewButtonBg);
end;

procedure TTbMainFormTests.TestAProblemIsMarkedAndJumpedTo;
var
  special: Boolean;
  markup: TSynSelectedColor;
begin
  WriteBytes(FDir + 'bad.tycss', '/* a */'#10'TyButton {'#10'/* '#$E4#$B8#$AD' */ color red;'#10);
  AssertTrue('opened', FForm.OpenFile(FDir + 'bad.tycss'));
  AssertTrue('F3: a problem', Length(FForm.Problems) > 0);
  AssertEquals('F3: the parse error', Ord(tlkParseError), Ord(FForm.Problems[0].Kind));
  AssertEquals('F3: line', 3, FForm.Problems[0].Line);
  AssertEquals('F3: byte column', 17, FForm.Problems[0].Col);
  AssertEquals('F3: one mark', 1, FForm.Editor.Marks.Count);
  AssertEquals('F3: on line 3', 3, FForm.Editor.Marks[0].Line);
  AssertEquals('F3: the badge', 1, FForm.ProblemsWin.BadgeValue);
  FForm.JumpToProblem(0);
  AssertEquals('F3: jumped to the column', 17, FForm.Editor.LogicalCaretXY.X);
  AssertEquals('F3: jumped to the line', 3, FForm.Editor.LogicalCaretXY.Y);
  markup := TSynSelectedColor.Create;
  try
    special := False;
    FForm.EditorSpecialLineMarkup(FForm.Editor, 3, special, markup);
    AssertTrue('F3: line 3 is tinted', special);
    special := False;
    FForm.EditorSpecialLineMarkup(FForm.Editor, 1, special, markup);
    AssertFalse('F3: line 1 is not', special);
  finally
    markup.Free;
  end;
end;

procedure TTbMainFormTests.TestAParseErrorKeepsThePreview;
var
  i: Integer;
begin
  FForm.Editor.Lines.Text := cMarkerDocMain;
  FForm.RefreshNow;
  AssertEquals('the marker is loaded', $123456, PreviewButtonBg);
  FForm.Editor.Lines.Text := 'TyButton { color: red';
  FForm.RefreshNow;
  AssertEquals('F4: the preview kept it', $123456, PreviewButtonBg);
  AssertTrue('F4: a parse error', TbHasParseError(FForm.Problems));
  for i := 0 to High(FForm.Problems) do
    AssertTrue('F4: not reported twice', FForm.Problems[i].Origin <> tpoLoad);
end;

procedure TTbMainFormTests.TestSaveKeepsTheBytes;
const
  cBytes = 'a {}'#13#10'b {}'#13#10;
begin
  WriteBytes(FDir + 'crlf.tycss', cBytes);
  AssertTrue('opened', FForm.OpenFile(FDir + 'crlf.tycss'));
  FForm.Editor.Modified := True;   { as after an edit that was undone by hand }
  AssertTrue('modified before saving', FForm.Editor.Modified);
  AssertTrue('F5: saved', FForm.SaveDocument);
  AssertTrue('F5: the same bytes', ReadBytes(FDir + 'crlf.tycss') = cBytes);
  AssertTrue('F5: not modified: ' + FForm.Bar.Caption, Pos('*', FForm.Bar.Caption) = 0);
  AssertEquals('F5: the recent list', ExpandFileName(FDir + 'crlf.tycss'), FForm.Settings.Recent[0]);
end;

procedure TTbMainFormTests.TestSaveAsForANewDocument;
begin
  TTbMainForm.SaveAsNameForTest := FDir + 'new.tycss';
  AssertTrue('F6: saved', FForm.SaveDocument);
  AssertTrue('F6: the file', FileExists(FDir + 'new.tycss'));
  AssertFalse('F6: no longer untitled', FForm.Doc.Untitled);
  AssertEquals('F6: its name', ExpandFileName(FDir + 'new.tycss'), FForm.Doc.FileName);
end;

procedure TTbMainFormTests.TestSavingABuiltinThemeHints;
var
  f: string;
begin
  WriteBytes(FDir + 'root' + PathDelim + 'scripts' + PathDelim + 'gen-builtinthemes.ps1', '');
  f := FDir + 'root' + PathDelim + 'themes' + PathDelim + 'builtin' + PathDelim + 'x.tycss';
  WriteBytes(f, 'TyButton { background: #123456; }'#10);
  AssertTrue('opened', FForm.OpenFile(f));
  AssertTrue('saved', FForm.SaveDocument);
  AssertTrue('F7: the status names the script: ' + FForm.Status.Panels[0].Text,
    Pos('gen-builtinthemes.ps1', FForm.Status.Panels[0].Text) > 0);
end;

procedure TTbMainFormTests.TestClosingAsks;
begin
  FForm.Editor.Lines.Text := cMarkerDocMain;
  FForm.Editor.Modified := True;
  TTbMainForm.SaveAsNameForTest := FDir + 'closed.tycss';
  TTbMainForm.PromptAnswerForTest := mrCancel;
  AssertFalse('F8: cancel keeps it open', FForm.CloseQuery);
  TTbMainForm.PromptAnswerForTest := mrNo;
  AssertTrue('F8: no closes', FForm.CloseQuery);
  AssertFalse('F8: without saving', FileExists(FDir + 'closed.tycss'));
  FForm.Editor.Modified := True;
  TTbMainForm.PromptAnswerForTest := mrYes;
  AssertTrue('F8: yes closes', FForm.CloseQuery);
  AssertTrue('F8: after saving', FileExists(FDir + 'closed.tycss'));
  AssertTrue('F8: it asked', FForm.AskCount >= 3);
end;

procedure TTbMainFormTests.TestNewFromABuiltinTheme;
begin
  FForm.NewFromBuiltin('win11');
  AssertEquals('F9: the theme', Unify(TbFromBuiltin('win11')), Unify(FForm.Editor.Lines.Text));
  AssertTrue('F9: the title names it: ' + FForm.Bar.Caption, Pos('win11', FForm.Bar.Caption) > 0);
  AssertTrue('F9: untitled', FForm.Doc.Untitled);
end;

procedure TTbMainFormTests.TestThePreviewCannotTouchTheTool;
var
  ver: Cardinal;
begin
  ver := TyDefaultController.Model.ThemeVersion;
  FForm.Editor.Lines.Text := '@@@';
  FForm.RefreshNow;
  FForm.Editor.Lines.Text := cMarkerDocMain;
  FForm.RefreshNow;
  AssertTrue('F10: the tool''s controller did not move', TyDefaultController.Model.ThemeVersion = ver);
  AssertTrue('F10: the problem list is on the tool''s theme',
    TTyCustomControlAccess(FForm.ProblemsList).ActiveController = TyDefaultController);
end;

procedure TTbMainFormTests.TestTheProjectListsItsUnits;
const
  cUnits: array[0..33] of string = ('themebuilder.lpr', 'tbmain.pas', 'tbpreview.pas',
    'tbsamplewin.pas', 'tbtemplates.pas', 'tbproblems.pas', 'tbdocument.pas',
    'tbsettings.pas', 'tbthemesource.pas', 'tbeditorlook.pas',
    'tbcssscan.pas', 'tbseeds.pas', 'tbseedsframe.pas', 'tbrules.pas', 'tbpick.pas',
    'tbcoverage.pas', 'tbcoverageform.pas', 'tbexport.pas', 'tbexportform.pas',
    'tbsnippets.pas', 'tbsnippetsform.pas',
    'ai/tbhttp.pas', 'ai/tbhttpwin.pas', 'ai/tbhttpcurl.pas', 'ai/tbsse.pas',
    'ai/tbaiformat.pas', 'ai/tbaiclient.pas', 'ai/tbaisettings.pas', 'ai/tbreference.pas',
    'ai/tbaisession.pas', 'tbdiff.pas', 'tbcompareform.pas', 'tbaisettingsform.pas',
    'tbaiframe.pas');
var
  lpi, dir, rel: string;
  sl: TStringList;
  files: TStringList;
  i: Integer;
begin
  dir := TbRepoDir + 'tools' + PathDelim + 'themebuilder' + PathDelim;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(dir + 'themebuilder.lpi');
    lpi := sl.Text;
  finally
    sl.Free;
  end;
  for i := 0 to High(cUnits) do
    AssertTrue('F11: the project lists ' + cUnits[i],
      Pos('<Filename Value="' + cUnits[i] + '"/>', lpi) > 0);
  AssertTrue('F11: SynEdit', Pos('<PackageName Value="SynEdit"/>', lpi) > 0);
  AssertTrue('F11: not the installed package', Pos('"tycontrols"', LowerCase(lpi)) = 0);
  AssertTrue('F11: the design-time sources', Pos('../../designtime', lpi) > 0);
  AssertTrue('F11: the ai folder is searched', Pos('<OtherUnitFiles Value=".;ai;', lpi) > 0);
  { every unit under the tool's folder, the ai folder included, by its path from there }
  files := FindAllFiles(dir, '*.pas', True);
  try
    AssertTrue('there are units on disk', files.Count >= 30);
    for i := 0 to files.Count - 1 do
    begin
      rel := StringReplace(ExtractRelativePath(dir, files[i]), PathDelim, '/', [rfReplaceAll]);
      if Copy(rel, 1, 4) = 'lib/' then Continue;
      AssertTrue('F11: on disk and in the project: ' + rel,
        Pos('<Filename Value="' + rel + '"/>', lpi) > 0);
    end;
  finally
    files.Free;
  end;
end;

procedure TTbMainFormTests.TestAnOutsideChangeIsOfferedOnce;
var
  f: string;
  asked: Integer;
begin
  f := FDir + 'watched.tycss';
  WriteBytes(f, 'TyButton { background: #111111; }'#10);
  AssertTrue('opened', FForm.OpenFile(f));
  WriteBytes(f, 'TyButton { background: #123456; }'#10'TyEdit { color: #222222; }'#10);
  TTbMainForm.PromptAnswerForTest := mrYes;
  FForm.CheckDiskNow;
  AssertEquals('F12: reloaded', 'TyButton { background: #123456; }'#10'TyEdit { color: #222222; }',
    Unify(FForm.Editor.Lines.Text));
  WriteBytes(f, 'TyButton { background: #654321; }'#10);
  TTbMainForm.PromptAnswerForTest := mrNo;
  FForm.CheckDiskNow;
  AssertEquals('F12: kept when told no', 'TyButton { background: #123456; }'#10'TyEdit { color: #222222; }',
    Unify(FForm.Editor.Lines.Text));
  asked := FForm.AskCount;
  FForm.CheckDiskNow;
  AssertEquals('F12: the same change is not offered again', asked, FForm.AskCount);
end;

procedure TTbMainFormTests.TestTheReloadQuestionWarnsOfUnsavedChanges;
var
  f: string;
begin
  f := FDir + 'w2.tycss';
  WriteBytes(f, 'TyButton { background: #111111; }'#10);
  AssertTrue('opened', FForm.OpenFile(f));
  WriteBytes(f, 'TyButton { background: #222222; }'#10#10);
  TTbMainForm.PromptAnswerForTest := mrNo;
  FForm.CheckDiskNow;
  AssertTrue('F13: asked', FForm.LastAsk <> '');
  AssertTrue('F13: nothing unsaved, no warning', Pos(rsTbReloadLoses, FForm.LastAsk) = 0);
  FForm.Editor.Modified := True;
  WriteBytes(f, 'TyButton { background: #333333; }'#10#10#10);
  FForm.CheckDiskNow;
  AssertTrue('F13: unsaved changes are warned about', Pos(rsTbReloadLoses, FForm.LastAsk) > 0);
end;

procedure TTbMainFormTests.TestOurOwnSaveIsNotAnOutsideChange;
var
  f: string;
  asked: Integer;
begin
  f := FDir + 'own.tycss';
  WriteBytes(f, 'TyButton { background: #111111; }'#10);
  AssertTrue('opened', FForm.OpenFile(f));
  FForm.Editor.Lines.Add('TyEdit { color: #222222; }');
  AssertTrue('saved', FForm.SaveDocument);
  asked := FForm.AskCount;
  FForm.CheckDiskNow;
  AssertEquals('F14: not asked', asked, FForm.AskCount);
end;

procedure TTbMainFormTests.TestTheEditorFollowsTheToolTheme;
var
  light, dark: TColor;
begin
  FForm.SetEditorAppearance('default', False);
  light := TbEditorColors(TyDefaultController).Background;
  AssertEquals('the editor is on the light ground', light, FForm.Editor.Color);
  FForm.SetEditorAppearance('default', True);
  dark := TbEditorColors(TyDefaultController).Background;
  AssertTrue('the two grounds differ', light <> dark);
  AssertEquals('F15: the editor followed', dark, FForm.Editor.Color);
end;

procedure TTbMainFormTests.Heard(Sender: TObject);
begin
  Inc(FHeard);
end;

{ The window listens to the tool's controller (the default one, which outlives it) and must
  stop when it goes. A sentinel inside its listener (ToolThemeChangedForTest, called before
  the listener touches the window) counts the calls: one while the window lives -- the
  sentinel is live -- and none after it is freed. The test used to free the window, fire
  Changed and assert True, which a dangling listener passes whenever the freed memory
  still reads. }
procedure TTbMainFormTests.TestTheListenerIsRemoved;
begin
  FHeard := 0;
  TTbMainForm.ToolThemeChangedForTest := @Heard;
  try
    TyDefaultController.Changed;
    AssertEquals('the window listens', 1, FHeard);
    FreeAndNil(FForm);
    FHeard := 0;
    TyDefaultController.Changed;
    AssertEquals('F16: the freed window no longer listens', 0, FHeard);
  finally
    TTbMainForm.ToolThemeChangedForTest := nil;
  end;
end;

procedure TTbMainFormTests.TestTheSettingsAreKept;
var
  ini: TIniFile;
begin
  FForm.SetEditorAppearance('xp', True);
  FForm.Preview.SetModern(True);
  AssertTrue('closes', FForm.CloseQuery);
  ini := TIniFile.Create(TTbMainForm.SettingsFileForTest);
  try
    AssertEquals('F17: the theme', 'xp', ini.ReadString('Editor', 'Theme', ''));
    AssertTrue('F17: dark', ini.ReadBool('Editor', 'Dark', False));
    AssertTrue('F17: modern', ini.ReadBool('Preview', 'Modern', False));
  finally
    ini.Free;
  end;
  FreeAndNil(FForm);
  TyDefaultController.ThemeName := 'default';
  FForm := TTbMainForm.Create(nil);
  AssertEquals('F17: the next window starts on it', 'xp', TyDefaultController.ThemeName);
  AssertTrue('F17: and the preview is modern', FForm.Preview.IsModern);
  AssertEquals('F17: its strip says so', 1, FForm.Preview.DensityCombo.ItemIndex);
end;

procedure TTbMainFormTests.TestProblemLinesTakeTheirColourFromTheTheme;
var
  special: Boolean;
  markup: TSynSelectedColor;
begin
  WriteBytes(FDir + 'bad.tycss', '/* a */'#10'TyButton {'#10'/* '#$E4#$B8#$AD' */ color red;'#10);
  AssertTrue('opened', FForm.OpenFile(FDir + 'bad.tycss'));
  markup := TSynSelectedColor.Create;
  try
    special := False;
    FForm.EditorSpecialLineMarkup(FForm.Editor, 3, special, markup);
    AssertTrue('the line is tinted', special);
    AssertEquals('F18: the error tint of the tool theme', FForm.Look.ErrorLine, markup.Background);
    AssertTrue('F18: which is not the ground', markup.Background <> FForm.Editor.Color);
  finally
    markup.Free;
  end;
end;

{ ---- the catalogues ---- }

function ToolDir: string;
begin
  Result := TbRepoDir + 'tools' + PathDelim + 'themebuilder' + PathDelim;
end;

function LoadLines(const AFileName: string): TStringList;
begin
  Result := TStringList.Create;
  Result.LoadFromFile(AFileName);
end;

{ The keys LCLTranslator looks up for a .lfm's texts: <root class>.<component>.<property>
  (or <root class>.<property> for the root), lower case -- for the string properties a
  person reads. Collection items (tree items, status panels) are skipped: they carry no
  text to translate here. }
procedure LfmKeys(const AFileName: string; AKeys: TStrings);
const
  cProps: array[0..7] of string = ('caption', 'hint', 'texthint', 'striphint', 'text',
    'message', 'description', 'title');
var
  lines, stack: TStringList;
  i, j, depth, inColl: Integer;
  ln, t, root, name, prop: string;
  p: Integer;
begin
  lines := LoadLines(AFileName);
  stack := TStringList.Create;
  try
    root := '';
    inColl := 0;
    for i := 0 to lines.Count - 1 do
    begin
      ln := lines[i];
      t := Trim(ln);
      if (Length(t) >= 3) and (Copy(t, Length(t) - 2, 3) = '= <') then
      begin
        Inc(inColl);
        Continue;
      end;
      if inColl > 0 then
      begin
        if (t = '>') or (Copy(t, Length(t) - 3, 4) = 'end>') then
          Dec(inColl);
        Continue;
      end;
      depth := 0;
      while (depth < Length(ln)) and (ln[depth + 1] = ' ') do Inc(depth);
      depth := depth div 2;
      if (Copy(t, 1, 7) = 'object ') or (Copy(t, 1, 7) = 'inline ') then
      begin
        name := Copy(t, 8, Pos(':', t) - 8);
        while stack.Count > depth do stack.Delete(stack.Count - 1);
        stack.Add(LowerCase(Trim(name)));
        if root = '' then
          root := LowerCase(Trim(Copy(t, Pos(':', t) + 1, MaxInt)));
        Continue;
      end;
      p := Pos(' = ''', t);
      if p = 0 then Continue;
      prop := LowerCase(Copy(t, 1, p - 1));
      for j := 0 to High(cProps) do
        if prop = cProps[j] then
        begin
          if depth <= 1 then
            AKeys.Add(root + '.' + prop)
          else
            AKeys.Add(root + '.' + stack[depth - 1] + '.' + prop);
          Break;
        end;
    end;
  finally
    stack.Free;
    lines.Free;
  end;
end;

procedure TTbMainFormTests.TestTheCatalogueCoversTheForms;
var
  want, have, po, forms: TStringList;
  i: Integer;
  k: string;
begin
  want := TStringList.Create;
  have := TStringList.Create;
  po := LoadLines(ToolDir + 'languages' + PathDelim + 'themebuilder.zh_CN.po');
  forms := FindAllFiles(ToolDir, '*.lfm', False);
  try
    want.Sorted := True;
    want.Duplicates := dupIgnore;
    have.Sorted := True;
    have.Duplicates := dupIgnore;
    AssertTrue('the forms', forms.Count >= 7);
    for i := 0 to forms.Count - 1 do
      LfmKeys(forms[i], want);
    AssertTrue('the forms have texts', want.Count > 50);
    AssertTrue('a menu item', want.IndexOf('ttbmainform.mnufile.caption') >= 0);
    AssertTrue('a frame control', want.IndexOf('ttbpreviewframe.btndefault.caption') >= 0);
    AssertTrue('a root caption', want.IndexOf('ttbsampleform.caption') >= 0);
    for i := 0 to po.Count - 1 do
      if Copy(po[i], 1, 3) = '#: ' then
      begin
        k := Trim(Copy(po[i], 4, MaxInt));
        if Copy(k, 1, 3) = 'ttb' then   { the code's keys start with the unit: tbmain. ... }
          have.Add(k);
      end;
    for i := 0 to want.Count - 1 do
      AssertTrue('I1: the catalogue translates ' + want[i], have.IndexOf(want[i]) >= 0);
    for i := 0 to have.Count - 1 do
      AssertTrue('I1: the catalogue has a key no form has: ' + have[i], want.IndexOf(have[i]) >= 0);
  finally
    want.Free;
    have.Free;
    po.Free;
    forms.Free;
  end;
end;

function FormatSpecs(const S: string): string;
var
  i: Integer;
begin
  Result := '';
  i := 1;
  while i < Length(S) do
  begin
    if S[i] = '%' then
    begin
      if S[i + 1] = '%' then
      begin
        Inc(i, 2);
        Continue;
      end;
      Inc(i);
      while (i <= Length(S)) and (S[i] in ['0'..'9', '.', '-', '*', ':']) do Inc(i);
      if i <= Length(S) then
        Result := Result + LowerCase(S[i]);
    end;
    Inc(i);
  end;
end;

procedure TTbMainFormTests.TestTheCatalogueEntriesAreWhole;
var
  po: TStringList;
  i, n: Integer;
  ident, id, str: string;
  fmt: Boolean;
begin
  po := LoadLines(ToolDir + 'languages' + PathDelim + 'themebuilder.zh_CN.po');
  try
    ident := '';
    fmt := False;
    id := '';
    n := 0;
    for i := 0 to po.Count - 1 do
    begin
      if Copy(po[i], 1, 3) = '#: ' then
      begin
        ident := Trim(Copy(po[i], 4, MaxInt));
        fmt := False;
      end
      else if Copy(po[i], 1, 3) = '#, ' then
        fmt := Pos('object-pascal-format', po[i]) > 0
      else if Copy(po[i], 1, 6) = 'msgid ' then
        id := Copy(po[i], 7, MaxInt)
      else if (Copy(po[i], 1, 7) = 'msgstr ') and (ident <> '') then
      begin
        str := Copy(po[i], 8, MaxInt);
        Inc(n);
        AssertTrue('I2: ' + ident + ' has a translation', (str <> '""') and (str <> ''));
        if fmt then
          AssertEquals('I2: ' + ident + ' keeps its placeholders', FormatSpecs(id), FormatSpecs(str));
        ident := '';
      end;
    end;
    AssertTrue('I2: entries were read', n > 50);
  finally
    po.Free;
  end;
end;

procedure TTbMainFormTests.TestTheTranslationsCoverTheCode;
var
  json: TJSONData;
  obj: TJSONObject;
  files, src, names: TStringList;
  i, j, p: Integer;
  uname, t, rs: string;
  inRs: Boolean;
begin
  names := TStringList.Create;
  names.Sorted := True;
  files := FindAllFiles(ToolDir, '*.pas', True);     { the ai folder too }
  src := TStringList.Create;
  try
    for i := 0 to files.Count - 1 do
    begin
      uname := LowerCase(ChangeFileExt(ExtractFileName(files[i]), ''));
      src.LoadFromFile(files[i]);
      inRs := False;
      for j := 0 to src.Count - 1 do
      begin
        t := Trim(src[j]);
        if LowerCase(t) = 'resourcestring' then
        begin
          inRs := True;
          Continue;
        end;
        if inRs then
        begin
          if (t = '') or (Copy(t, 1, 1) = '{') or (Copy(t, 1, 2) = '//') then Continue;
          p := Pos('=', t);
          if (Copy(t, 1, 2) = 'rs') and (p > 0) then
          begin
            rs := LowerCase(Trim(Copy(t, 1, p - 1)));
            names.Add(uname + '.' + rs);
          end
          else if Copy(t, 1, 1) <> '''' then
            inRs := False;   { the section ended (type, function, ...) }
        end;
      end;
    end;
    AssertTrue('the tool has resourcestrings', names.Count > 40);
    json := GetJSON(ReadBytes(ToolDir + 'languages' + PathDelim + 'themebuilder.zh_CN.json'));
    try
      obj := json as TJSONObject;
      for i := 0 to obj.Count - 1 do
        AssertTrue('I3: the translation of ' + obj.Names[i] + ' is for a resourcestring',
          names.IndexOf(obj.Names[i]) >= 0);
      for i := 0 to names.Count - 1 do
        AssertTrue('I3: ' + names[i] + ' has a translation', obj.IndexOfName(names[i]) >= 0);
    finally
      json.Free;
    end;
  finally
    src.Free;
    files.Free;
    names.Free;
  end;
end;

procedure TTbMainFormTests.TestTheLibraryCatalogueIsACopy;
begin
  AssertTrue('I4: the tool carries the library''s catalogue as it is',
    ReadBytes(ToolDir + 'languages' + PathDelim + 'tycontrols.zh_CN.po') =
    ReadBytes(TbRepoDir + 'languages' + PathDelim + 'tycontrols.strconsts.zh_CN.po'));
end;

{ A variable that leads back to itself: the window comes through and the problem list
  has it on a line. A crash without the guard in Css.Values; no row on a line without
  ThemeLint's ScanVarCycles (the first document is evaluated by nothing). }
procedure TTbMainFormTests.TestAVariableCycleIsAProblem;
const
  cDocs: array[0..3] of string = (
    ':root { --a: var(--a); }',
    ':root {'#10'  --a: var(--b);'#10'  --b: var(--a);'#10'}'#10'TyButton { background: var(--a); }',
    '@mode light {'#10'  :root { --surface: darken(var(--surface), 5%); }'#10'}'#10 +
      '@mode dark { :root { --surface: #202020; } }',
    ':root { --r: --r2; --r2: --r; }'#10'TyButton { border-width: var(--r); }');
var
  i, k: Integer;
  found: Boolean;
begin
  for i := 0 to High(cDocs) do
  begin
    FForm.Editor.Lines.Text := cDocs[i];
    FForm.RefreshNow;
    found := False;
    for k := 0 to High(FForm.Problems) do
      if (FForm.Problems[k].Origin = tpoLint) and (FForm.Problems[k].Kind = tlkBadValue)
         and (FForm.Problems[k].Line > 0)
         and (Pos('refers back to itself', FForm.Problems[k].Text) > 0) then
        found := True;
    AssertTrue('a row on a line for document ' + IntToStr(i), found);
    AssertTrue('and a mark in the gutter', FForm.Editor.Marks.Count > 0);
  end;
end;

{ The preview's dark switch, used as a person uses it (its OnChange): a document that does
  not resolve in dark is refused, and the reason is in the problem list. It used to be lost
  on the way: the switch's notice reloaded the document, and a good load cleared the
  refusal. A refresh of the same text keeps it; while the text does not parse it is not
  listed (it is about the version still shown, not the text being written); a new document
  clears it. }
procedure TTbMainFormTests.TestARefusedDarkReachesTheProblemList;
const
  cLightOnly = '@mode light { :root { --x: #ffffff; } } @mode dark { :root { --z: #000000; } } ' +
    'TyButton { background: var(--x); }';

  function Refusals: Integer;
  var
    i: Integer;
    head: string;
  begin
    Result := 0;
    head := Format(rsTbModeFailed, [rsTbModeDark, '']);
    for i := 0 to High(FForm.Problems) do
      if (FForm.Problems[i].Origin = tpoLoad) and (Pos(head, FForm.Problems[i].Text) = 1) then
        Inc(Result);
  end;

begin
  FForm.Editor.Lines.Text := cLightOnly;
  FForm.RefreshNow;
  AssertFalse('shown in light', FForm.Preview.IsDark);
  AssertEquals('nothing refused yet', 0, Refusals);
  FForm.Preview.DarkSwitch.Checked := True;
  AssertFalse('dark was refused', FForm.Preview.IsDark);
  AssertFalse('the switch sprang back', FForm.Preview.DarkSwitch.Checked);
  AssertEquals('F19: the reason is in the list', 1, Refusals);
  FForm.RefreshNow;
  AssertEquals('F19: a refresh of the same text keeps it', 1, Refusals);
  FForm.Editor.Lines.Text := cLightOnly + ' TyEdit { color: red';
  FForm.RefreshNow;
  AssertTrue('a parse error', TbHasParseError(FForm.Problems));
  AssertEquals('F19: not listed while the text does not parse', 0, Refusals);
  FForm.Editor.Lines.Text := TbMinimalTemplate;
  FForm.RefreshNow;
  AssertEquals('F19: a new document clears it', 0, Refusals);
end;

{ A save that fails half-way through writing (FailWriteForTest, inside the real
  SaveToFile) leaves the file byte for byte as it was, no stray file beside it, the
  document still modified and on its old stamp -- so the watch does not take our own failed
  write for another program's. The file used to be cut to nothing first (fmCreate on it). }
procedure TTbMainFormTests.TestAFailedSaveLeavesTheFile;
const
  cBytes = 'TyButton { background: #111111; }'#10'TyEdit { color: #222222; }'#10;
var
  f: string;
  asked: Integer;
  files: TStringList;
begin
  f := FDir + 'keep.tycss';
  WriteBytes(f, cBytes);
  AssertTrue('opened', FForm.OpenFile(f));
  FForm.Editor.Lines.Add('TyPanel { color: #333333; }');
  FForm.Editor.Modified := True;
  TTbDocument.FailWriteForTest := True;
  try
    AssertFalse('F20: the save failed', FForm.SaveDocument);
  finally
    TTbDocument.FailWriteForTest := False;
  end;
  AssertTrue('F20: the file is as it was', ReadBytes(f) = cBytes);
  files := FindAllFiles(FDir, '*', False);
  try
    AssertEquals('F20: nothing left beside it', 1, files.Count);
  finally
    files.Free;
  end;
  AssertTrue('F20: still modified', FForm.Editor.Modified);
  asked := FForm.AskCount;
  FForm.CheckDiskNow;
  AssertEquals('F20: our failed write is not an outside change', asked, FForm.AskCount);
  AssertTrue('F20: and the next save goes through', FForm.SaveDocument);
  AssertTrue('F20: with the new text', Pos('TyPanel', ReadBytes(f)) > 0);
end;

{ The settings file cannot be written (read-only): closing still closes, and says nothing
  -- saving the settings is the tool's convenience, not the user's work. Red without the
  try/except around FSettings.Save (TIniFile raises from UpdateFile). The recent list is
  written as soon as a file is opened, not only at close. }
procedure TTbMainFormTests.TestAReadOnlySettingsFileDoesNotKeepTheWindowOpen;
var
  f, ini: string;
  raised: Boolean;
  sl: TStringList;
begin
  ini := TTbMainForm.SettingsFileForTest;
  f := FDir + 'recent.tycss';
  WriteBytes(f, 'TyButton { background: #111111; }'#10);
  AssertTrue('opened', FForm.OpenFile(f));
  AssertTrue('F21: the settings were written on opening', FileExists(ini));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(ini);
    AssertTrue('F21: with the recent file', Pos(ExpandFileName(f), sl.Text) > 0);
  finally
    sl.Free;
  end;
  AssertEquals('made read-only', 0, FileSetAttr(ini, faReadOnly));
  try
    raised := False;
    try
      AssertTrue('F21: it closes', FForm.CloseQuery);
    except
      raised := True;
    end;
    AssertFalse('F21: and nothing was raised', raised);
  finally
    FileSetAttr(ini, 0);
  end;
end;

{ A rule left open on the last line: the parser stops at the end of Lines.Text, which ends
  with a line break -- one line past the last the editor has. The problem, its gutter mark
  and the jump belong on the last line, after its last character. }
procedure TTbMainFormTests.TestAnErrorAtTheEndIsOnTheLastLine;
begin
  FForm.Editor.Lines.Text := 'TyButton {'#10'  color: red;';
  AssertEquals('two lines in the editor', 2, FForm.Editor.Lines.Count);
  FForm.RefreshNow;
  AssertTrue('a parse error', TbHasParseError(FForm.Problems));
  AssertEquals('F22: on the last line', 2, FForm.Problems[0].Line);
  AssertEquals('F22: after its last character', Length('  color: red;') + 1, FForm.Problems[0].Col);
  AssertEquals('F22: one mark', 1, FForm.Editor.Marks.Count);
  AssertEquals('F22: in the gutter of line 2', 2, FForm.Editor.Marks[0].Line);
  FForm.JumpToProblem(0);
  AssertEquals('F22: the caret goes there', 2, FForm.Editor.LogicalCaretXY.Y);
end;

{ Opening a recent file fails: only a file that is gone leaves the list. One another program
  holds exclusively (as a share that is down, or a file being written) stays. }
procedure TTbMainFormTests.TestAFileThatCannotBeReadStaysRecent;
var
  held, gone: string;
  lock: TFileStream;
begin
  held := FDir + 'held.tycss';
  gone := FDir + 'gone.tycss';
  WriteBytes(held, 'TyButton { background: #111111; }'#10);
  WriteBytes(gone, 'TyButton { background: #222222; }'#10);
  AssertTrue('opened', FForm.OpenFile(gone));
  AssertTrue('opened', FForm.OpenFile(held));
  AssertEquals('both are recent', 2, FForm.Settings.Recent.Count);
  lock := TFileStream.Create(held, fmOpenRead or fmShareExclusive);
  try
    AssertFalse('F23: a file held by another program does not open', FForm.OpenFile(held));
  finally
    lock.Free;
  end;
  AssertTrue('F23: and stays in the list', FForm.Settings.Recent.IndexOf(ExpandFileName(held)) >= 0);
  AssertTrue('removed', DeleteFile(gone));
  AssertFalse('a file that is gone does not open', FForm.OpenFile(ExpandFileName(gone)));
  AssertTrue('F23: and leaves the list', FForm.Settings.Recent.IndexOf(ExpandFileName(gone)) < 0);
  AssertEquals('F23: the menu follows', FForm.Settings.Recent.Count, FForm.MnuRecent.Count);
end;

{ A menu caption reads & as the accelerator mark: a path with one in it is shown as it is
  (&& in the caption), and the item still opens that path. }
procedure TTbMainFormTests.TestAnAmpersandInARecentPathIsShown;
var
  f: string;
begin
  f := FDir + 'salt&pepper.tycss';
  WriteBytes(f, 'TyButton { background: #111111; }'#10);
  AssertTrue('opened', FForm.OpenFile(f));
  AssertEquals('F24: the caption doubles the ampersand',
    StringReplace(ExpandFileName(f), '&', '&&', [rfReplaceAll]), FForm.MnuRecent.Items[0].Caption);
  AssertEquals('F24: the list keeps the path', ExpandFileName(f), FForm.Settings.Recent[0]);
end;

{ The side bar's strip shows its tool windows as icons; their names are in hints, which a
  control only shows when ShowHint is on (the .lfm). }
procedure TTbMainFormTests.TestTheSideBarShowsItsHints;
begin
  AssertTrue('F25: the strip shows hints', FForm.SideBar.ShowHint);
  AssertTrue('F25: and the problems window has one', FForm.ProblemsWin.StripHint <> '');
end;

{ The problem marks bring their own images; SynEdit's bookmarks (Ctrl+Shift+0..9) must not
  draw from them -- they did, the mark list being set as the bookmark images. }
procedure TTbMainFormTests.TestTheMarksDoNotTakeTheBookmarkImages;
begin
  FForm.Editor.Lines.Text := 'TyButton {'#10'  frobnicate: 1px;'#10'}';
  FForm.RefreshNow;
  AssertEquals('a mark', 1, FForm.Editor.Marks.Count);
  AssertTrue('F26: the mark has the problem images', FForm.Editor.Marks[0].ImageList = FForm.GutterIcons);
  AssertTrue('F26: the bookmarks do not', FForm.Editor.BookMarkOptions.BookmarkImages <> FForm.GutterIcons);
end;

{ A file that cannot be opened or saved is reported with the error sign, not the question
  mark every message used to wear; a question (reload?) keeps the question mark. }
procedure TTbMainFormTests.TestAFailureIsAnErrorNotAQuestion;
var
  f: string;
begin
  AssertFalse('a missing file', FForm.OpenFile(FDir + 'nowhere.tycss'));
  AssertEquals('F27: opening failed: an error', Ord(mtError), Ord(FForm.LastAskType));
  f := FDir + 'q.tycss';
  WriteBytes(f, 'TyButton { background: #111111; }'#10);
  AssertTrue('opened', FForm.OpenFile(f));
  TTbDocument.FailWriteForTest := True;
  try
    AssertFalse('the save fails', FForm.SaveDocument);
  finally
    TTbDocument.FailWriteForTest := False;
  end;
  AssertEquals('F27: saving failed: an error', Ord(mtError), Ord(FForm.LastAskType));
  WriteBytes(f, 'TyButton { background: #222222; }'#10#10);
  FForm.CheckDiskNow;
  AssertEquals('F27: the reload is a question', Ord(mtConfirmation), Ord(FForm.LastAskType));
end;

{ A line is edited (a character typed and taken back) and the caret moves on: its trailing
  spaces stay, and the save writes the bytes that were read. SynEdit's default trims them
  when the caret leaves an edited line. }
procedure TTbMainFormTests.TestTrailingSpacesOfAnEditedLineAreKept;
const
  cLine1 = 'TyButton { color: #111111; }   ';
  cBytes = cLine1 + #10'TyEdit { color: #222222; }'#10;
var
  f: string;
begin
  f := FDir + 'spaces.tycss';
  WriteBytes(f, cBytes);
  AssertTrue('opened', FForm.OpenFile(f));
  FForm.Editor.LogicalCaretXY := Point(Length(cLine1) + 1, 1);
  FForm.Editor.CommandProcessor(ecChar, 'x', nil);
  AssertEquals('typed', cLine1 + 'x', FForm.Editor.Lines[0]);
  FForm.Editor.CommandProcessor(ecDeleteLastChar, #0, nil);
  FForm.Editor.LogicalCaretXY := Point(1, 2);
  AssertEquals('F28: the edited line keeps its spaces', cLine1, FForm.Editor.Lines[0]);
  AssertTrue('saved', FForm.SaveDocument);
  AssertTrue('F28: the same bytes', ReadBytes(f) = cBytes);
end;

{ ---- phase 2: the seeds page, Ctrl+click, the coverage check, export, snippets ---- }

const
  cRulesDocMain = 'TyButton { }'#10'TyButton.primary { }'#10'TyButton.primary:hover { }'#10 +
    'TyEdit, TyButton.primary { }';

{ each line without its trailing blanks, LF breaks, no trailing ones }
function TrimmedLines(const S: string): string;
var
  sl: TStringList;
  i: Integer;
begin
  sl := TStringList.Create;
  try
    sl.Text := S;
    Result := '';
    for i := 0 to sl.Count - 1 do
    begin
      if i > 0 then Result := Result + #10;
      Result := Result + TrimRight(sl[i]);
    end;
  finally
    sl.Free;
  end;
end;

procedure CtrlPress(AControl: TControl);
begin
  AControl.Perform(LM_LBUTTONDOWN, MK_LBUTTON or MK_CONTROL, 0);
  AControl.Perform(LM_LBUTTONUP, 0, 0);
end;

function PrimaryBg(AForm: TTbMainForm): Integer;
begin
  Result := Integer(Cardinal(AForm.Preview.Controller.Model.ResolveStyle('TyButton', 'primary', [])
    .Background.Color) and $FFFFFF);
end;

procedure TTbMainFormTests.TestTheSeedsPageIsBuilt;
begin
  AssertTrue('F29: the frame is in its host', FForm.Seeds.Parent = FForm.SeedsHost);
  AssertTrue('F29: the seeds page shows first', FForm.SideBar.ActiveWindow = FForm.SeedsWin);
  AssertEquals('F29: two columns for the minimal template', 2, Length(FForm.Seeds.Columns));
  AssertEquals('F29: light', 'light', FForm.Seeds.Columns[0]);
  AssertEquals('F29: dark', 'dark', FForm.Seeds.Columns[1]);
  AssertFalse('F29: not broken', FForm.Seeds.Broken);
end;

{ A character typed first, then a seed changed from the page: one Undo takes the seed back
  and leaves the character -- the seed's edits are one step of their own. }
procedure TTbMainFormTests.TestASeedChangeIsOneUndoStep;
var
  typed: string;
begin
  FForm.Editor.LogicalCaretXY := Point(4, 1);   { inside the header comment: still parses }
  FForm.Editor.CommandProcessor(ecChar, 'x', nil);
  typed := FForm.Editor.Lines.Text;
  AssertTrue('typed', Pos('/* xA minimal', typed) = 1);
  AssertTrue('F30: applied', FForm.Seeds.ApplyValue(0, 0, '#123456'));
  AssertTrue('F30: the light accent', Pos('--accent: #123456;', FForm.Editor.Lines.Text) > 0);
  AssertTrue('F30: the dark one as it was', Pos('--accent: #60A5FA;', FForm.Editor.Lines.Text) > 0);
  AssertEquals('F30: the preview has it', $123456, PrimaryBg(FForm));
  FForm.Editor.Undo;
  AssertEquals('F30: one undo: the seed back, the x still there', Unify(typed), Unify(FForm.Editor.Lines.Text));
end;

procedure TTbMainFormTests.TestEditsOnAnotherTextAreRefused;
var
  t, u: string;
  e: TTbTextEdits;
begin
  t := FForm.Editor.Lines.Text;
  AssertEquals('the page scanned it', t, FForm.Seeds.ScannedText);
  u := StringReplace(t, '#1F2937', '#222222', []);
  AssertTrue('a different text', u <> t);
  FForm.Editor.Lines.Text := u;      { not refreshed }
  SetLength(e, 1);
  e[0] := TbEdit(1, 1, 'x');
  AssertFalse('F31: edits on the old text are refused', FForm.ApplyEdits(t, e));
  AssertEquals('F31: the text is untouched', Unify(u), Unify(FForm.Editor.Lines.Text));
  AssertTrue('F31: the page catches up first', FForm.Seeds.ApplyValue(0, 0, '#ABCDEF'));
  AssertTrue('F31: landed on the new text', Pos('#222222', FForm.Editor.Lines.Text) > 0);
  AssertTrue('F31: with the seed', Pos('--accent: #ABCDEF;', FForm.Editor.Lines.Text) > 0);
end;

procedure TTbMainFormTests.TestTheSeedsFollowTheText;
begin
  FForm.Editor.Lines.Text := '@mode light { :root { --accent: #ABCDEF; } }'#10 +
    '@mode dark { :root { --accent: #222222; } }';
  AssertTrue('not yet', FForm.Seeds.ResolvedText(0, 0) <> '#ABCDEF');
  FForm.RefreshNow;
  AssertEquals('F32: the page follows', '#ABCDEF', FForm.Seeds.ResolvedText(0, 0));
end;

procedure TTbMainFormTests.TestCtrlClickGoesToTheRule;
begin
  FForm.Editor.Lines.Text := cRulesDocMain;
  CtrlPress(FForm.Preview.BtnPrimary);
  AssertEquals('F33: first x', 1, FForm.Editor.LogicalCaretXY.X);
  AssertEquals('F33: first y', 2, FForm.Editor.LogicalCaretXY.Y);
  CtrlPress(FForm.Preview.BtnPrimary);
  AssertEquals('F33: next x', 9, FForm.Editor.LogicalCaretXY.X);
  AssertEquals('F33: next y', 4, FForm.Editor.LogicalCaretXY.Y);
  CtrlPress(FForm.Preview.BtnPrimary);
  AssertEquals('F33: round again x', 1, FForm.Editor.LogicalCaretXY.X);
  AssertEquals('F33: round again y', 2, FForm.Editor.LogicalCaretXY.Y);
end;

procedure TTbMainFormTests.TestCtrlClickAddsARule;
var
  t, want: string;
begin
  t := TrimmedLines(FForm.Editor.Lines.Text);
  CtrlPress(FForm.Preview.TagDanger);
  want := 'TyTag.danger {'#10#10'}';
  AssertEquals('F34: an empty rule at the end', want,
    Copy(TrimmedLines(FForm.Editor.Lines.Text), Length(TrimmedLines(FForm.Editor.Lines.Text)) - Length(want) + 1, MaxInt));
  AssertEquals('F34: the caret on the line in the braces', FForm.Editor.Lines.Count - 1,
    FForm.Editor.LogicalCaretXY.Y);
  AssertEquals('F34: indented', 3, FForm.Editor.LogicalCaretXY.X);
  FForm.Editor.Undo;
  AssertEquals('F34: one undo takes it away', t, TrimmedLines(FForm.Editor.Lines.Text));
end;

procedure TTbMainFormTests.TestTheCoverageCheckReadsTheDocument;
var
  f: TTbCoverageForm;
  i: Integer;
  found: Boolean;
begin
  FForm.Editor.Lines.Text := 'TyRibbon { }';
  f := FForm.BuildCoverageForm;
  try
    found := False;
    for i := 0 to f.LstNotShown.Items.Count - 1 do
      if Pos('TyRibbon', f.LstNotShown.Items[i]) = 1 then
        found := True;
    AssertTrue('F35: the ribbon is listed', found);
  finally
    f.Free;
  end;
end;

{ A file with LF breaks, opened on Windows: the editor's Lines.Text has CRLF; the bundle's
  theme.tycss has the bytes a save would write (the file's own). }
procedure TTbMainFormTests.TestTheExportTakesTheSavedBytes;
var
  bytes, err: string;
  f: TTbExportForm;
begin
  bytes := StringReplace(ReadBytes(TbThemesDir + 'green.tycss'), #13#10, #10, [rfReplaceAll]);
  WriteBytes(FDir + 'theme' + PathDelim + 'green.tycss', bytes);
  WriteBytes(FDir + 'theme' + PathDelim + 'assets' + PathDelim + 'background.jpg',
    ReadBytes(TbThemesDir + 'assets' + PathDelim + 'background.jpg'));
  AssertTrue('opened', FForm.OpenFile(FDir + 'theme' + PathDelim + 'green.tycss'));
  AssertTrue('F36: what a save would write', FForm.EntryBytes = bytes);
  f := FForm.BuildExportForm;
  try
    AssertEquals('F36: the picture goes in', 1, Length(f.Files));
    AssertEquals('F36: as referred to', 'assets/background.jpg', f.Files[0].Archive);
    f.EdtTarget.Text := FDir + 'bundle';
    AssertTrue('F36: exported: ' + err, f.DoExport(err));
  finally
    f.Free;
  end;
  AssertTrue('F36: the file''s bytes', ReadBytes(FDir + 'bundle' + PathDelim + 'theme.tycss') = bytes);
end;

procedure TTbMainFormTests.TestTheSnippetsNameTheFile;
var
  f: TTbSnippetsForm;
begin
  WriteBytes(FDir + 'green.tycss', ReadBytes(TbThemesDir + 'green.tycss'));
  AssertTrue('opened', FForm.OpenFile(FDir + 'green.tycss'));
  AssertEquals('the name', 'green', FForm.SnippetName);
  f := FForm.BuildSnippetsForm;
  try
    AssertTrue('F37: the file', Pos('''green.tycss''', f.MemoFile.Lines.Text) > 0);
    AssertTrue('F37: the folder', Pos('''green''', f.MemoFolder.Lines.Text) > 0);
  finally
    f.Free;
  end;
end;

procedure TTbMainFormTests.TestTheViewMenuShowsTheSidePages;
begin
  AssertFalse('open', FForm.SideBar.Collapsed);
  AssertTrue('on the seeds', FForm.SideBar.ActiveWindow = FForm.SeedsWin);
  FForm.MnuSeedsClick(nil);
  AssertTrue('F38: the page showing: folded away', FForm.SideBar.Collapsed);
  FForm.MnuSeedsClick(nil);
  AssertFalse('F38: opened again', FForm.SideBar.Collapsed);
  AssertTrue('F38: on the seeds', FForm.SideBar.ActiveWindow = FForm.SeedsWin);
  FForm.MnuProblemsClick(nil);
  AssertFalse('F38: still open', FForm.SideBar.Collapsed);
  AssertTrue('F38: on the problems', FForm.SideBar.ActiveWindow = FForm.ProblemsWin);
end;

function MedianOf(var A: array of Int64): Int64;
var
  i, j: Integer;
  x: Int64;
begin
  for i := 0 to High(A) do
    for j := i + 1 to High(A) do
      if A[j] < A[i] then
      begin
        x := A[i];
        A[i] := A[j];
        A[j] := x;
      end;
  Result := A[Length(A) div 2];
end;

{ How long a refresh takes on a big theme, in its three parts, each the median of five on a
  text changed each time (no cache helps): the lint, the preview's load and probe, the seeds
  page (its scan and second model, worked through as when it shows). Printed for the
  sign-off. The seeds page does less than the preview (no probe, no controls): when it costs
  more than the preview, its work has grown (twice what it should, at least) -- red. The whole
  refresh red only past ten times what it should take. }
procedure TTbMainFormTests.TestHowLongARefreshTakes;
var
  lint, prev, seeds, total, again: array[0..4] of Int64;
  i: Integer;
  t0: Int64;
  css, dir, err: string;
  base: TStringList;
  probs: TTbProblems;
begin
  WriteBytes(FDir + 'auto.tycss', ReadBytes(TbThemesDir + 'auto.tycss'));
  AssertTrue('opened', FForm.OpenFile(FDir + 'auto.tycss'));
  dir := FForm.Doc.BaseDir;
  base := TStringList.Create;
  try
    TbBaseVarNames(base);
    for i := 0 to 4 do
    begin
      css := FForm.Editor.Lines.Text + '/* ' + IntToStr(i) + ' */' + LineEnding;
      t0 := GetTickCount64;
      probs := TbCollectProblems(css, dir, False, base);
      lint[i] := GetTickCount64 - t0;
      AssertTrue('clean', not TbHasParseError(probs));
      FForm.Preview.Controller.Model.RefreshSystemTokens;   { no cached resolves }
      t0 := GetTickCount64;
      AssertTrue('loads', FForm.Preview.LoadDocument(css, dir, err));
      prev[i] := GetTickCount64 - t0;
      t0 := GetTickCount64;
      FForm.Seeds.UpdateFrom(css, dir, False);
      FForm.Seeds.CatchUp;
      seeds[i] := GetTickCount64 - t0;
      t0 := GetTickCount64;
      FForm.Seeds.UpdateFrom(css, dir, False);
      FForm.Seeds.CatchUp;
      again[i] := GetTickCount64 - t0;
      FForm.Preview.Controller.Model.RefreshSystemTokens;
      t0 := GetTickCount64;
      FForm.RefreshNow;
      total[i] := GetTickCount64 - t0;
    end;
  finally
    base.Free;
  end;
  WriteLn(Format('TTbMainFormTests.TestHowLongARefreshTakes: auto.tycss, medians of five -- ' +
    'lint %d ms, preview %d ms, seeds page %d ms (the same text again %d ms); ' +
    'a whole refresh with the page hidden %d ms',
    [MedianOf(lint), MedianOf(prev), MedianOf(seeds), MedianOf(again), MedianOf(total)]));
  AssertTrue('K1: the seeds page costs less than the preview', MedianOf(seeds) <= MedianOf(prev));
  AssertTrue('K1: the same text again costs next to nothing', MedianOf(again) * 4 <= MedianOf(seeds) + 4);
  AssertTrue('a refresh in reasonable time', MedianOf(total) < 1500);
end;

{ The page is hidden (here: the window is never shown): a refresh takes the text and loads
  nothing; the page works it through when it is shown (the side bar window's OnShow), or
  when something is asked of it; the same text again loads nothing. }
procedure TTbMainFormTests.TestTheSeedsPageWaitsTillItIsShown;
var
  n: Integer;
begin
  AssertEquals('two columns', 2, Length(FForm.Seeds.Columns));
  n := FForm.Seeds.EvalLoads;
  FForm.Editor.Lines.Text := '@mode light { :root { --accent: #ABCDEF; } }'#10 +
    '@mode dark { :root { --accent: #222222; } }';
  FForm.RefreshNow;
  AssertEquals('K2: hidden: nothing loaded', n, FForm.Seeds.EvalLoads);
  FForm.SeedsWin.OnShow(FForm.SeedsWin);
  AssertEquals('K2: shown: loaded', n + 1, FForm.Seeds.EvalLoads);
  AssertEquals('K2: the new value', '#ABCDEF', FForm.Seeds.ResolvedText(0, 0));
  FForm.RefreshNow;
  FForm.SeedsWin.OnShow(FForm.SeedsWin);
  AssertEquals('K2: the same text: nothing loaded', n + 1, FForm.Seeds.EvalLoads);
  FForm.Editor.Lines.Text := '@mode light { :root { --accent: #ABCDEE; } }'#10 +
    '@mode dark { :root { --accent: #222222; } }';
  FForm.RefreshNow;
  AssertEquals('K2: asked: worked through', '#ABCDEE', FForm.Seeds.ResolvedText(0, 0));
end;

{ Radius steps one after another are one undo step back to where the first one started; a
  keystroke in between makes them two. }
procedure TTbMainFormTests.TestRadiusStepsAreOneUndoStep;
var
  t0, t1: string;
begin
  t0 := FForm.Editor.Lines.Text;
  FForm.Seeds.RadiusSpin(0).Value := 7;
  FForm.Seeds.FlushRadius;
  FForm.Seeds.RadiusSpin(0).Value := 8;
  FForm.Seeds.FlushRadius;
  FForm.Seeds.RadiusSpin(0).Value := 9;
  FForm.Seeds.FlushRadius;
  AssertTrue('K3: the light radius is 9', Pos('--radius: 9px;', FForm.Editor.Lines.Text) > 0);
  AssertEquals('K3: the preview has it', 9, FForm.Preview.Controller.Model.ResolveMetric('--radius', -1));
  FForm.Editor.Undo;
  AssertEquals('K3: one undo takes all three back', Unify(t0), Unify(FForm.Editor.Lines.Text));
  FForm.RefreshNow;
  FForm.Seeds.RadiusSpin(0).Value := 7;
  FForm.Seeds.FlushRadius;
  FForm.Editor.LogicalCaretXY := Point(4, 1);   { inside the header comment }
  FForm.Editor.CommandProcessor(ecChar, 'x', nil);
  t1 := FForm.Editor.Lines.Text;
  FForm.Seeds.RadiusSpin(0).Value := 8;
  FForm.Seeds.FlushRadius;
  FForm.Editor.Undo;
  AssertEquals('K3: a keystroke between: the second step alone', Unify(t1), Unify(FForm.Editor.Lines.Text));
end;

{ The rows size themselves: a note longer than its column wraps and the row grows to hold
  it. They used to be cut at one line (a fixed 18 px label in a fixed 78 px row). The
  window is never shown here, and the LCL sizes nothing for a window that is not (autosizing
  waits for it): what is checked is what the layout is built from -- each note asks for
  more height for a longer text at its column's width, and every row and note is set to
  follow what its contents ask for, each note held under its swatch at the swatch's width. }
procedure TTbMainFormTests.TestALongNoteTakesASecondLine;
var
  s: TTbSeedsFrame;
  seed, col, w, hShort, hLong: Integer;
  note: TTyLabel;
  row: TControl;
  above: TControl;
begin
  s := FForm.Seeds;
  for seed := 0 to TbSeedCount - 1 do
    for col := 0 to 1 do
    begin
      note := s.Note(seed, col);
      row := note.Parent;
      if seed = TbRadiusSeed then above := s.RadiusSpin(col) else above := s.Swatch(seed, col);
      AssertTrue('L1: the row grows with its notes ' + IntToStr(seed), row.AutoSize);
      AssertTrue('L1: the note grows with its text ' + note.Name, note.AutoSize);
      AssertTrue('L1: and wraps ' + note.Name, note.WordWrap);
      AssertTrue('L1: under its swatch ' + note.Name, note.AnchorSideTop.Control = above);
      AssertTrue('L1: as wide as it, left ' + note.Name, note.AnchorSideLeft.Control = above);
      AssertTrue('L1: as wide as it, right ' + note.Name, note.AnchorSideRight.Control = above);
    end;
  note := s.Note(0, 0);
  w := 0;
  note.Caption := 'x';
  note.GetPreferredSize(w, hShort);
  note.Caption := rsTbSeedOverridden + ' ' + rsTbSeedOverridden;
  w := 0;
  note.GetPreferredSize(w, hLong);
  AssertTrue('L1: a long note asks for more lines', hLong > hShort);
  AssertTrue('L1: the mode note grows too', s.ModeNote.AutoSize and s.ModeNote.WordWrap);
end;

{ A spin box step still waiting its 250 ms when the file is saved goes into the file. }
procedure TTbMainFormTests.TestAWaitingRadiusIsSaved;
begin
  FForm.Seeds.RadiusSpin(1).Value := 11;
  AssertTrue('waiting', FForm.Seeds.RadiusPending);
  AssertTrue('saved', FForm.SaveTo(FDir + 'r.tycss'));
  AssertTrue('K4: the waiting radius is in the file', Pos('--radius: 11px;', ReadBytes(FDir + 'r.tycss')) > 0);
  AssertFalse('K4: and waits no more', FForm.Seeds.RadiusPending);
end;

{ The preview's hooks and the seeds page outlive FormDestroy by a little (they are freed
  with the window): neither calls back into it. The window goes with its hooks live (the
  sample window's too) and a pick just made -- and freeing it raises nothing. }
procedure TTbMainFormTests.TestAWindowGoesWithItsHooks;
var
  f: TTbMainForm;
  raised: string;
begin
  f := TTbMainForm.Create(nil);
  try
    f.Preview.BuildSampleWindow;
    AssertTrue('F39: the sample window is hooked too',
      f.Preview.Picker.HookCount > FForm.Preview.Picker.HookCount);
    CtrlPress(f.Preview.BtnPrimary);
    AssertTrue('F39: the hooks are live: the pick added the rule',
      Pos('TyButton.primary {', f.Editor.Lines.Text) > 0);
  except
    f.Free;
    raise;
  end;
  raised := '';
  try
    f.Free;
  except
    on E: Exception do
      raised := E.ClassName + ': ' + E.Message;
  end;
  AssertEquals('F39: gone without a fault', '', raised);
end;

{ An editor with no line at all: Lines.Text is '', with no final break for an edit to stop
  before. A block added to it is that block and nothing more -- not one empty line after. }
procedure TTbMainFormTests.TestAnEmptyEditorGetsNoExtraLine;
var
  src, want: string;
  scan: TTbCssScan;
  edits: TTbTextEdits;
begin
  FForm.Editor.Lines.Text := '';
  FForm.RefreshNow;
  src := FForm.Editor.Lines.Text;
  AssertEquals('no line at all', '', src);
  scan := TbScanCss(src);
  try
    edits := TbSeedSetEdits(scan, TbDetectEol(src), 0, '', '#ABCDEF', False);
  finally
    scan.Free;
  end;
  want := TbApplyEdits(src, edits);
  AssertTrue('applied', FForm.ApplyEdits(src, edits));
  AssertEquals('G1: the block and its final break, no empty line after', want, FForm.Editor.Lines.Text);
  AssertEquals('G1: three lines', 3, FForm.Editor.Lines.Count);
  FForm.Editor.Lines.Text := '';
  FForm.RefreshNow;
  FForm.JumpToRule('TyTag', 'danger');
  AssertEquals('G1: an empty rule in an empty editor', 'TyTag.danger {' + LineEnding + '  ' + LineEnding + '}' + LineEnding,
    FForm.Editor.Lines.Text);
  AssertEquals('G1: the caret in the braces (line)', 2, FForm.Editor.LogicalCaretXY.Y);
  AssertEquals('G1: the caret in the braces (column)', 3, FForm.Editor.LogicalCaretXY.X);
end;

{ ---- what a control looks like, every field a paint reads ---- }

function ColorHex(C: TTyColor): string;
begin
  Result := IntToHex(Cardinal(C), 8);
end;

function StyleText(const S: TTyStyleSet): string;
var
  p: TTyProp;
begin
  Result := '[';
  for p := Low(TTyProp) to High(TTyProp) do
    if p in S.Present then
      Result := Result + IntToStr(Ord(p)) + ',';
  Result := Result + '] bg=' + IntToStr(Ord(S.Background.Kind)) + '/' + ColorHex(S.Background.Color)
    + '/' + ColorHex(S.Background.GradFrom) + '>' + ColorHex(S.Background.GradTo)
    + ' txt=' + ColorHex(S.TextColor) + ' bd=' + ColorHex(S.BorderColor) + '/'
    + IntToStr(S.BorderWidth) + '/' + IntToStr(Ord(S.BorderStyle)) + '/' + IntToStr(Ord(S.RenderStyle))
    + ' rad=' + IntToStr(S.BorderRadius) + '/' + IntToStr(S.Radius.TL) + ',' + IntToStr(S.Radius.TR)
    + ',' + IntToStr(S.Radius.BR) + ',' + IntToStr(S.Radius.BL)
    + ' pad=' + IntToStr(S.Padding.Left) + ',' + IntToStr(S.Padding.Top) + ','
    + IntToStr(S.Padding.Right) + ',' + IntToStr(S.Padding.Bottom)
    + ' fnt=' + S.FontName + '/' + IntToStr(S.FontSize) + '/' + IntToStr(S.FontWeight)
    + ' op=' + IntToStr(Round(S.Opacity * 1000))
    + ' sh=' + ColorHex(S.ShadowColor) + '/' + IntToStr(S.ShadowBlur) + '/'
    + IntToStr(S.ShadowOffset.X) + ',' + IntToStr(S.ShadowOffset.Y)
    + ' ol=' + ColorHex(S.OutlineColor) + '/' + IntToStr(S.OutlineWidth) + '/' + IntToStr(S.OutlineOffset);
end;

const
  cLookStates: array[0..9] of TTyStateSet = ([], [tysHover], [tysActive], [tysFocused],
    [tysDisabled], [tysSelected], [tysHover, tysFocused], [tysSelected, tysHover],
    [tysHover, tysActive], [tysDisabled, tysFocused]);

{ AText's look for AKey with each class of AClasses ('' first) in every state, light and dark }
function LookOf(const AText, AKey: string; AClasses: TStrings): string;
var
  m: TTyStyleModel;
  md, c, s: Integer;
  mode: string;
begin
  Result := '';
  m := TTyStyleModel.Create;
  try
    m.LoadFromSource(TTbTextThemeSource.Create(AText, ''));
    for md := 0 to 1 do
    begin
      if md = 0 then mode := 'light' else mode := 'dark';
      m.SetMode(mode);
      for c := 0 to AClasses.Count - 1 do
        for s := 0 to High(cLookStates) do
          Result := Result + mode + '/' + AClasses[c] + '/' + IntToStr(s) + ': '
            + StyleText(m.ResolveStyle(AKey, AClasses[c], cLookStates[s])) + LineEnding;
    end;
  finally
    m.Free;
  end;
end;

{ '' and every variant the base or AText knows for AKey }
function ClassesOf(const AText, AKey: string): TStringList;
var
  m: TTyStyleModel;
begin
  Result := TStringList.Create;
  Result.Add('');
  m := TTyStyleModel.Create;
  try
    m.LoadFromSource(TTbTextThemeSource.Create(AText, ''));
    m.GetVariantsForType(AKey, Result);
  finally
    m.Free;
  end;
end;

{ The review found it: Ctrl+click on a control the minimal template has no rule for added an
  empty plain rule, and an empty plain rule takes the whole base layer away from the typeKey
  (UserHasTypeKey) -- the edit, the button, the check box and the list lost every style.
  Now the rule starts as the base's rules for it: every variant in every state, light and
  dark, resolves exactly as before. }
procedure TTbMainFormTests.TestCtrlClickKeepsTheLook;
const
  cKeys: array[0..3] of string = ('TyEdit', 'TyButton', 'TyCheckBox', 'TyListBox');
var
  ctl: array[0..3] of TControl;
  i: Integer;
  before, after, shown: string;
  classes: TStringList;
  scan: TTbCssScan;
  hits: TTbOffsets;
begin
  ctl[0] := FForm.Preview.EdtText;
  ctl[1] := FForm.Preview.BtnDefault;
  ctl[2] := FForm.Preview.ChkOn;
  ctl[3] := FForm.Preview.LstSample;
  for i := 0 to High(cKeys) do
  begin
    before := FForm.Editor.Lines.Text;
    classes := ClassesOf(before, cKeys[i]);
    try
      shown := StyleText(FForm.Preview.Controller.Model.ResolveStyle(cKeys[i], '', [tysHover]));
      CtrlPress(ctl[i]);
      after := FForm.Editor.Lines.Text;
      scan := TbScanCss(after);
      try
        hits := TbFindRuleSelectors(scan, cKeys[i], '');
      finally
        scan.Free;
      end;
      AssertEquals('H1: one plain rule for ' + cKeys[i], 1, Length(hits));
      AssertEquals('H1: the caret on its first declaration (line) ' + cKeys[i],
        TbOffsetToPoint(after, hits[0]).Y + 1, FForm.Editor.LogicalCaretXY.Y);
      AssertEquals('H1: the caret on its first declaration (column) ' + cKeys[i], 3,
        FForm.Editor.LogicalCaretXY.X);
      AssertEquals('H1: ' + cKeys[i] + ' looks as it did', LookOf(before, cKeys[i], classes),
        LookOf(after, cKeys[i], classes));
      AssertEquals('H1: and the preview shows it so', shown,
        StyleText(FForm.Preview.Controller.Model.ResolveStyle(cKeys[i], '', [tysHover])));
    finally
      classes.Free;
    end;
  end;
end;

{ A rule for a variant does not take the base layer away (UserHasTypeKey wants a plain one):
  Ctrl+click on the primary button adds it empty, and nothing changes. }
procedure TTbMainFormTests.TestCtrlClickOnAVariantTakesNothingAway;
var
  before, after: string;
  classes: TStringList;
begin
  before := FForm.Editor.Lines.Text;
  classes := ClassesOf(before, 'TyButton');
  try
    CtrlPress(FForm.Preview.BtnPrimary);
    after := FForm.Editor.Lines.Text;
    AssertTrue('H2: an empty variant rule at the end',
      Pos('TyButton.primary {' + LineEnding + '  ' + LineEnding + '}', after) > 0);
    AssertEquals('H2: no plain rule', 0, Pos('TyButton {', after));
    AssertEquals('H2: every variant and state as before', LookOf(before, 'TyButton', classes),
      LookOf(after, 'TyButton', classes));
  finally
    classes.Free;
  end;
end;

{ The document already has `TyEdit:focus`, written over the base's: the base's rules come in
  before it, so its own still has the last word, and the plain look in every state is what
  it was. }
procedure TTbMainFormTests.TestTheBaseRulesGoBeforeTheDocumentsOwn;
var
  before, after: string;
  plain: TStringList;
  scan: TTbCssScan;
  hits: TTbOffsets;
begin
  FForm.Editor.Lines.Text := TbMinimalTemplate + LineEnding + 'TyEdit:focus { border-color: #FF0000; }' + LineEnding;
  FForm.RefreshNow;
  before := FForm.Editor.Lines.Text;
  plain := TStringList.Create;
  try
    plain.Add('');
    CtrlPress(FForm.Preview.EdtText);
    after := FForm.Editor.Lines.Text;
    scan := TbScanCss(after);
    try
      hits := TbFindRuleSelectors(scan, 'TyEdit', '');
    finally
      scan.Free;
    end;
    AssertEquals('H3: one plain rule', 1, Length(hits));
    AssertTrue('H3: before the document''s own TyEdit:focus', hits[0] < Pos('TyEdit:focus { border-color: #FF0000; }', after));
    AssertEquals('H3: the plain look in every state', LookOf(before, 'TyEdit', plain), LookOf(after, 'TyEdit', plain));
  finally
    plain.Free;
  end;
end;

{ A file the document imports has `TyEdit { ... }`: the base layer is gone for TyEdit
  already, and copying the base's rules in would put them over the imported ones. The rule
  is added empty, and the edit keeps the imported look. }
procedure TTbMainFormTests.TestAnImportedPlainRuleIsNotCopiedOver;
begin
  WriteBytes(FDir + 'mine.tycss', 'TyEdit { background: #123456; color: #ABCDEF; }'#10);
  WriteBytes(FDir + 'doc.tycss', '@import "mine.tycss";'#10);
  AssertTrue('opened', FForm.OpenFile(FDir + 'doc.tycss'));
  AssertEquals('the imported look', $123456,
    Integer(Cardinal(FForm.Preview.Controller.Model.ResolveStyle('TyEdit', '', []).Background.Color) and $FFFFFF));
  CtrlPress(FForm.Preview.EdtText);
  AssertTrue('H4: an empty rule', Pos('TyEdit {' + LineEnding + '  ' + LineEnding + '}', FForm.Editor.Lines.Text) > 0);
  AssertEquals('H4: nothing of the base copied in', 0, Pos('TyEdit:', FForm.Editor.Lines.Text));
  AssertEquals('H4: the imported look stays', $123456,
    Integer(Cardinal(FForm.Preview.Controller.Model.ResolveStyle('TyEdit', '', []).Background.Color) and $FFFFFF));
end;

{ The first list of the coverage check names TyButon because the document has a rule for it
  -- here only `TyButon:hover` and `TyButon.big`. A double click goes there (and to the next
  one, again), and adds nothing; a typeKey with no rule at all still gets one. }
procedure TTbMainFormTests.TestTheCoverageCheckGoesToAnyRuleOfTheType;
var
  t, before: string;
  plain: TStringList;
  caret: Integer;
begin
  FForm.Editor.Lines.Text := 'TyButon:hover { color: #FF0000; }' + LineEnding + LineEnding +
    '  TyButon.big { color: #00FF00; }' + LineEnding;
  FForm.RefreshNow;
  t := FForm.Editor.Lines.Text;
  FForm.JumpToTypeKey('TyButon');
  AssertEquals('I1: nothing added', t, FForm.Editor.Lines.Text);
  AssertEquals('I1: at the first (line)', 1, FForm.Editor.LogicalCaretXY.Y);
  AssertEquals('I1: at the first (column)', 1, FForm.Editor.LogicalCaretXY.X);
  FForm.JumpToTypeKey('TyButon');
  AssertEquals('I1: then the next (line)', 3, FForm.Editor.LogicalCaretXY.Y);
  AssertEquals('I1: then the next (column)', 3, FForm.Editor.LogicalCaretXY.X);
  AssertEquals('I1: still nothing added', t, FForm.Editor.Lines.Text);
  plain := TStringList.Create;
  try
    plain.Add('');
    before := FForm.Editor.Lines.Text;
    FForm.JumpToTypeKey('TyFormSurface');
    AssertTrue('I1: a typeKey with no rule gets one', Pos('TyFormSurface {', FForm.Editor.Lines.Text) > 0);
    { the base has no rule for TyFormSurface (it is left out on purpose): the empty plain rule
      takes away a base layer that has nothing for it -- nothing changes }
    AssertEquals('I1: the base has nothing to copy', '', TbBaseRulesText('TyFormSurface', LineEnding, caret));
    AssertEquals('I1: and the empty rule changes nothing', LookOf(before, 'TyFormSurface', plain),
      LookOf(FForm.Editor.Lines.Text, 'TyFormSurface', plain));
  finally
    plain.Free;
  end;
end;

{ The review found it: splitting a one-mode theme copied --radius into both @mode blocks,
  and any @mode block wins over the density pack's :root -- the modern density's 8px radius
  was gone from the preview. Now the split leaves --radius in the :root; a radius set for
  one mode on purpose (answering No) is the one way to get that, and the question says so. }
procedure TTbMainFormTests.TestASplitKeepsTheModernRadius;
begin
  FForm.Editor.Lines.Text := TyBuiltinThemeCss;
  FForm.RefreshNow;
  AssertTrue('modern', FForm.Preview.SetModern(True));
  AssertEquals('the modern radius', 8, FForm.Preview.Controller.Model.ResolveMetric('--radius', -1));
  AssertTrue('split', FForm.Seeds.SplitModes);
  AssertEquals('two columns', 2, Length(FForm.Seeds.Columns));
  AssertEquals('J1: still the modern radius after the split', 8,
    FForm.Preview.Controller.Model.ResolveMetric('--radius', -1));
  AssertEquals('J1: the page shows the document''s', '6px', FForm.Seeds.ResolvedText(TbRadiusSeed, 0));
  TTbMainForm.PromptAnswerForTest := mrYes;
  AssertTrue('J1: changed for both modes', FForm.Seeds.ApplyValue(TbRadiusSeed, 0, '9px'));
  AssertTrue('J1: the question names the density', Pos('density', FForm.LastAsk) > 0);
  AssertEquals('J1: the density still wins over :root', 8,
    FForm.Preview.Controller.Model.ResolveMetric('--radius', -1));
  TTbMainForm.PromptAnswerForTest := mrNo;
  AssertTrue('J1: changed for light only', FForm.Seeds.ApplyValue(TbRadiusSeed, 0, '10px'));
  AssertEquals('J1: in the light block it wins over the density (asked first)', 10,
    FForm.Preview.Controller.Model.ResolveMetric('--radius', -1));
end;

{ ---- phase 3: the AI page ---- }

function BlueMinimal: string;
begin
  Result := StringReplace(TbMinimalTemplate, '--accent: #3B82F6;', '--accent: #ABCDEF;', []);
end;

{ a service to talk to, and the scripted model in place of its client }
function TTbMainFormTests.ScriptedAi: TScriptedBackend;
begin
  FForm.AiSettings.Put(TbPresetProfile(tapCustom));
  FForm.Ai.RefreshProfiles;
  Result := TScriptedBackend.Create;
  FForm.Ai.Session.Backend := Result;
end;

{ what the comparison / settings window would be answered with; the handlers below act
  on it as the user would }
procedure TTbMainFormTests.ModalAccept(Sender: TObject);
begin
  Inc(FModals);
  if Sender is TTbCompareForm then
  begin
    TTbCompareForm(Sender).BtnAcceptClick(nil);
    TTbCompareForm(Sender).ModalResult := mrOk;
  end;
end;

procedure TTbMainFormTests.ModalDiscard(Sender: TObject);
begin
  Inc(FModals);
  if Sender is TTbCompareForm then
    TTbCompareForm(Sender).ModalResult := mrCancel;
end;

procedure TTbMainFormTests.ModalLeave(Sender: TObject);
begin
  Inc(FModals);
  if Sender is TCustomForm then
    TCustomForm(Sender).ModalResult := mrCancel;
end;

procedure TTbMainFormTests.ModalOllama(Sender: TObject);
begin
  Inc(FModals);
  if Sender is TTbAiSettingsForm then
  begin
    TTbAiSettingsForm(Sender).AddPreset(tapOllama);
    if TTbAiSettingsForm(Sender).Commit then
      TTbAiSettingsForm(Sender).ModalResult := mrOk;
  end;
end;

function TTbMainFormTests.PreviewPrimaryBg: Integer;
begin
  Result := Integer(Cardinal(FForm.Preview.Controller.Model.ResolveStyle('TyButton', 'primary', [])
    .Background.Color) and $FFFFFF);
end;

procedure TTbMainFormTests.TestTheAiPageIsBuilt;
begin
  AssertEquals('M1: three side windows', 3, FForm.SideBar.WindowCount);
  AssertTrue('M1: the AI page last', FForm.SideBar.Windows[2] = FForm.AiWin);
  AssertTrue('M1: the frame is in its host', FForm.Ai.Parent = FForm.AiHost);
  AssertFalse('M1: nothing to generate with', FForm.Ai.BtnGenerate.Enabled);
  AssertEquals('M1: says so', rsTbAiNoProfile, FForm.Ai.LblStatus.Caption);
  AssertTrue('M1: the AI settings sit with the test settings: ' + FForm.AiSettings.IniFile,
    Pos(ExcludeTrailingPathDelimiter(FDir), FForm.AiSettings.IniFile) = 1);
end;

procedure TTbMainFormTests.TestGenerateCompareAcceptUndo;
var
  b: TScriptedBackend;
begin
  b := ScriptedAi;
  b.Add(TbAnswerWith(BlueMinimal));
  TTbMainForm.ShowModalForTest := @ModalAccept;
  FForm.Ai.EdtPrompt.Text := 'blue';
  FForm.Ai.GenerateClick(nil);
  AssertEquals('M2: the comparison was shown', 1, FModals);
  AssertTrue('M2: the editor has it', Pos('--accent: #ABCDEF;', FForm.Editor.Lines.Text) > 0);
  AssertEquals('M2: the preview has it', $ABCDEF, PreviewPrimaryBg);
  AssertEquals('M2: accepted', 1, PtrInt(FForm.Ai.Session.History.Objects[0]));
  FForm.Editor.Undo;
  AssertEquals('M2: one undo takes it back', Unify(TbMinimalTemplate), Unify(FForm.Editor.Lines.Text));
end;

procedure TTbMainFormTests.TestAcceptingKeepsTheCaret;
var
  b: TScriptedBackend;
  text, cand: string;
begin
  { a whole-text replacement would move the caret: shown first, then undone }
  text := FForm.Editor.Lines.Text;
  cand := TbNormalizeEol(BlueMinimal);
  FForm.Editor.LogicalCaretXY := Point(2, 3);
  AssertTrue('replaced whole', FForm.ApplyEdits(text, [TbEdit(1, Length(text) + 1 - Length(LineEnding),
    Copy(cand, 1, Length(cand) - Length(LineEnding)))]));
  AssertFalse('a whole replacement moves the caret',
    (FForm.Editor.LogicalCaretXY.X = 2) and (FForm.Editor.LogicalCaretXY.Y = 3));
  FForm.Editor.Undo;
  AssertEquals('back', Unify(TbMinimalTemplate), Unify(FForm.Editor.Lines.Text));

  b := ScriptedAi;
  b.Add(TbAnswerWith(BlueMinimal));
  TTbMainForm.ShowModalForTest := @ModalAccept;
  FForm.Editor.LogicalCaretXY := Point(2, 3);
  FForm.Ai.EdtPrompt.Text := 'blue';
  FForm.Ai.GenerateClick(nil);
  AssertTrue('accepted', Pos('--accent: #ABCDEF;', FForm.Editor.Lines.Text) > 0);
  AssertEquals('M3: the caret line', 3, FForm.Editor.LogicalCaretXY.Y);
  AssertEquals('M3: the caret column', 2, FForm.Editor.LogicalCaretXY.X);
end;

procedure TTbMainFormTests.TestEditedSinceAsksFirst;
var
  b: TScriptedBackend;
  o: TTbAiOutcome;
  added: string;
begin
  b := ScriptedAi;
  b.Add(TbAnswerWith(BlueMinimal));
  TTbMainForm.ShowModalForTest := @ModalLeave;
  FForm.Ai.EdtPrompt.Text := 'blue';
  FForm.Ai.GenerateClick(nil);
  o := FForm.Ai.Session.Outcome;
  AssertTrue('a candidate', o.HasCandidate);
  FForm.Editor.Lines.Add('/* added */');
  added := FForm.Editor.Lines.Text;
  TTbMainForm.PromptAnswerForTest := mrNo;
  AssertFalse('M4: not accepted', FForm.AcceptCandidate(o.BaseText, o.Candidate));
  AssertEquals('M4: the text stays', added, FForm.Editor.Lines.Text);
  AssertEquals('M4: it asked', rsTbAiEditedSince, FForm.LastAsk);
  TTbMainForm.PromptAnswerForTest := mrYes;
  AssertTrue('M4: accepted', FForm.AcceptCandidate(o.BaseText, o.Candidate));
  AssertEquals('M4: the AI''s version', Unify(BlueMinimal), Unify(FForm.Editor.Lines.Text));
  FForm.Editor.Undo;
  AssertEquals('M4: one undo goes back to the edited text', Unify(added), Unify(FForm.Editor.Lines.Text));
end;

procedure TTbMainFormTests.TestATrialSurvivesARefresh;
var
  b: TScriptedBackend;
  f: TTbCompareForm;
begin
  FForm.Editor.Lines.Text := cMarkerDocMain;
  FForm.RefreshNow;
  AssertEquals('the editor''s version', $123456, PreviewButtonBg);
  b := ScriptedAi;
  b.Add(TbAnswerWith('TyButton { background: #654321; }'));
  TTbMainForm.ShowModalForTest := @ModalLeave;
  FForm.Ai.EdtPrompt.Text := 'darker';
  FForm.Ai.GenerateClick(nil);
  f := FForm.BuildCompareForm;
  try
    f.TrialCheck.Checked := True;
    AssertEquals('M5: the trial is shown', $654321, PreviewButtonBg);
    FForm.Editor.Lines.Add('/* typed */');
    FForm.RefreshNow;
    AssertEquals('M5: a refresh keeps the trial', $654321, PreviewButtonBg);
    f.TrialCheck.Checked := False;
    AssertEquals('M5: the editor''s version again', $123456, PreviewButtonBg);
  finally
    f.Free;
  end;
end;

procedure TTbMainFormTests.TestANewDocumentStartsAfresh;
var
  b: TScriptedBackend;
  f: string;
begin
  b := ScriptedAi;
  b.Add(TbAnswerWith(BlueMinimal));
  TTbMainForm.ShowModalForTest := @ModalDiscard;
  FForm.Ai.EdtPrompt.Text := 'blue';
  FForm.Ai.GenerateClick(nil);
  AssertEquals('one request', 1, FForm.Ai.Session.History.Count);
  FForm.NewMinimal;
  AssertEquals('M6: a new document forgets', 0, FForm.Ai.Session.History.Count);
  { a reload of the same document does not }
  f := FDir + 'ai.tycss';
  WriteBytes(f, TbMinimalTemplate);
  AssertTrue('opened', FForm.OpenFile(f));
  FForm.Ai.GenerateClick(nil);
  AssertEquals('one request again', 1, FForm.Ai.Session.History.Count);
  WriteBytes(f, TbMinimalTemplate + '/* changed outside */'#10);
  TTbMainForm.PromptAnswerForTest := mrYes;
  FForm.CheckDiskNow;
  AssertTrue('reloaded', Pos('changed outside', FForm.Editor.Lines.Text) > 0);
  AssertEquals('M6: a reload keeps the conversation', 1, FForm.Ai.Session.History.Count);
end;

procedure TTbMainFormTests.TestTheProblemsBoxFollows;
var
  f: string;
begin
  f := FDir + 'broken.tycss';
  WriteBytes(f, 'TyButton { color: red'#10);
  AssertTrue('opened', FForm.OpenFile(f));
  AssertTrue('M7: ticked for a broken file', FForm.Ai.ChkProblems.Checked);
  FForm.Editor.Lines.Text := cMarkerDocMain;
  FForm.RefreshNow;
  AssertFalse('M7: unticked once fixed', FForm.Ai.ChkProblems.Checked);
  FForm.Ai.ChkProblems.Checked := True;           { the user's own choice }
  FForm.Editor.Lines.Text := 'TyButton { color: red';
  FForm.RefreshNow;
  FForm.Editor.Lines.Text := cMarkerDocMain;
  FForm.RefreshNow;
  AssertTrue('M7: the user''s choice holds', FForm.Ai.ChkProblems.Checked);
end;

procedure TTbMainFormTests.TestDiscardChangesNothing;
var
  b: TScriptedBackend;
  before: string;
begin
  b := ScriptedAi;
  b.Add(TbAnswerWith(BlueMinimal));
  TTbMainForm.ShowModalForTest := @ModalDiscard;
  before := FForm.Editor.Lines.Text;
  FForm.Ai.EdtPrompt.Text := 'blue';
  FForm.Ai.GenerateClick(nil);
  AssertEquals('the comparison was shown', 1, FModals);
  AssertEquals('M8: the text stays', before, FForm.Editor.Lines.Text);
  AssertEquals('M8: not used', 2, PtrInt(FForm.Ai.Session.History.Objects[0]));
  AssertTrue('M8: it can be shown again', FForm.Ai.BtnShowCompare.Enabled);
end;

procedure TTbMainFormTests.TestTheSettingsWindowIsWired;
begin
  TTbMainForm.ShowModalForTest := @ModalOllama;
  FForm.MnuAiSettingsClick(nil);
  AssertEquals('the settings were shown', 1, FModals);
  AssertEquals('M9: the page lists it', 1, FForm.Ai.ProfileCombo.Items.Count);
  AssertTrue('M9: sent to localhost: ' + FForm.Ai.LblSentTo.Caption,
    Pos('localhost', FForm.Ai.LblSentTo.Caption) > 0);
  AssertTrue('M9: generate is possible', FForm.Ai.BtnGenerate.Enabled);
end;

procedure TTbMainFormTests.TestStopIsWired;
var
  b: TScriptedBackend;
begin
  b := ScriptedAi;
  b.Hold := True;
  FForm.Ai.EdtPrompt.Text := 'blue';
  FForm.Ai.GenerateClick(nil);
  AssertTrue('M10: stop is offered', FForm.Ai.BtnStop.Enabled);
  AssertFalse('M10: generate is not', FForm.Ai.BtnGenerate.Enabled);
  FForm.Ai.StopClick(nil);
  AssertEquals('M10: the backend was told', 1, b.Cancels);
  b.ReleaseWith(aekCancelled);
  AssertEquals('M10: says so', rsTbAiCancelled, FForm.Ai.LblStatus.Caption);
  AssertTrue('M10: generate again', FForm.Ai.BtnGenerate.Enabled);
end;

procedure TTbMainFormTests.TestClosingWhileGenerating;
var
  b: TScriptedBackend;
  cancelled, freed: Integer;
begin
  b := ScriptedAi;
  b.Hold := True;
  FForm.Ai.EdtPrompt.Text := 'blue';
  FForm.Ai.GenerateClick(nil);
  cancelled := TScriptedBackend.Cancelled;
  freed := TScriptedBackend.Freed;
  FreeAndNil(FForm);
  AssertTrue('M11: the backend was told to stop', TScriptedBackend.Cancelled > cancelled);
  AssertTrue('M11: and freed', TScriptedBackend.Freed > freed);
  CheckSynchronize(50);
end;

procedure TTbMainFormTests.TestTheAnswerStreamsIn;
var
  b: TScriptedBackend;
  s: string;
  i: Integer;
  t0: QWord;
begin
  b := ScriptedAi;
  s := '';
  for i := 1 to 600 do
    s := s + Format('/* line %d of the answer */', [i]) + #10;
  b.Add(s, aekNone, 200, 30);
  b.HoldDone := True;
  FForm.Ai.EdtPrompt.Text := 'long';
  FForm.Ai.GenerateClick(nil);
  AssertTrue('M12: the flush timer is running', FForm.Ai.FlushTimer.Enabled);
  t0 := GetTickCount64;
  FForm.Ai.FlushTimerTimer(nil);
  WriteLn(Format('M12: 600 lines into the output box in %d ms', [GetTickCount64 - t0]));
  AssertTrue(Format('M12: %d lines shown', [FForm.Ai.OutputMemo.Lines.Count]),
    FForm.Ai.OutputMemo.Lines.Count >= 600);
  TTbMainForm.ShowModalForTest := @ModalLeave;
  b.FinishHeld;
end;

initialization
  RegisterTest(TTbMainFormTests);
end.
