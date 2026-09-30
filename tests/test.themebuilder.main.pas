unit test.themebuilder.main;
{ The theme builder's main window (phase 1), built for real and never shown (as the terminal
  example's tests do). Every question it asks is answered by PromptAnswerForTest, Save As
  takes SaveAsNameForTest and the settings go to a file in a temporary folder -- no test
  path shows a window or touches the user's configuration. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, Controls, tyControls.Controller, tbmain;

type
  TTbMainFormTests = class(TTestCase)
  private
    FDir: string;
    FForm: TTbMainForm;
    FThemeName, FMode: string;
    FDensity: TTyDensity;
    procedure WriteBytes(const AFileName, ABytes: string);
    function ReadBytes(const AFileName: string): string;
    function Unify(const S: string): string;
    function PreviewButtonBg: Integer;
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
  end;

implementation

uses
  FileUtil, IniFiles, Graphics, SynEdit, SynHighlighterCss, SynEditMiscClasses, tyControls.Base,
  tyControls.ThemeLint, tbproblems, tbtemplates, tbeditorlook, test.themebuilder.golden;

const
  { a document whose one value no base theme has }
  cMarkerDocMain = 'TyButton { background: #123456; }';

type
  TTyCustomControlAccess = class(TTyCustomControl);

var
  GMainSeq: Integer = 0;

procedure TTbMainFormTests.SetUp;
begin
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
  FForm := TTbMainForm.Create(nil);
end;

procedure TTbMainFormTests.TearDown;
begin
  FreeAndNil(FForm);
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
  AssertEquals('F1: one side window', 1, FForm.SideBar.WindowCount);
  AssertTrue('F1: the problems', FForm.SideBar.Windows[0] = FForm.ProblemsWin);
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
  cUnits: array[0..9] of string = ('themebuilder.lpr', 'tbmain.pas', 'tbpreview.pas',
    'tbsamplewin.pas', 'tbtemplates.pas', 'tbproblems.pas', 'tbdocument.pas',
    'tbsettings.pas', 'tbthemesource.pas', 'tbeditorlook.pas');
var
  lpi, dir: string;
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
  files := FindAllFiles(dir, '*.pas', False);
  try
    AssertTrue('there are units on disk', files.Count >= 9);
    for i := 0 to files.Count - 1 do
      AssertTrue('F11: on disk and in the project: ' + ExtractFileName(files[i]),
        Pos('<Filename Value="' + ExtractFileName(files[i]) + '"/>', lpi) > 0);
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

procedure TTbMainFormTests.TestTheListenerIsRemoved;
begin
  FreeAndNil(FForm);
  TyDefaultController.Changed;   { would call into the freed window if it still listened }
  AssertTrue('F16: no access violation', True);
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

initialization
  RegisterTest(TTbMainFormTests);
end.
