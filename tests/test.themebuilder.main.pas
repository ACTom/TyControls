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
    procedure TestTheCatalogueCoversTheForms;
    procedure TestTheCatalogueEntriesAreWhole;
    procedure TestTheTranslationsCoverTheCode;
    procedure TestTheLibraryCatalogueIsACopy;
  end;

implementation

uses
  FileUtil, IniFiles, Graphics, fpjson, jsonparser, SynEdit, SynHighlighterCss, SynEditMiscClasses, tyControls.Base,
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
  want, have, po: TStringList;
  i: Integer;
  k: string;
begin
  want := TStringList.Create;
  have := TStringList.Create;
  po := LoadLines(ToolDir + 'languages' + PathDelim + 'themebuilder.zh_CN.po');
  try
    want.Sorted := True;
    want.Duplicates := dupIgnore;
    have.Sorted := True;
    have.Duplicates := dupIgnore;
    LfmKeys(ToolDir + 'tbmain.lfm', want);
    LfmKeys(ToolDir + 'tbpreview.lfm', want);
    LfmKeys(ToolDir + 'tbsamplewin.lfm', want);
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
  unitName, t, rs: string;
  inRs: Boolean;
begin
  names := TStringList.Create;
  names.Sorted := True;
  files := FindAllFiles(ToolDir, '*.pas', False);
  src := TStringList.Create;
  try
    for i := 0 to files.Count - 1 do
    begin
      unitName := LowerCase(ChangeFileExt(ExtractFileName(files[i]), ''));
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
            names.Add(unitName + '.' + rs);
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

initialization
  RegisterTest(TTbMainFormTests);
end.
