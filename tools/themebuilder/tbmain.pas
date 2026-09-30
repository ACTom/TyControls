unit tbmain;
{ The theme builder's main window: a side-bar workbench (the Problems page), the .tycss
  editor in the middle, the preview on the right.

  Typing restarts a 300 ms timer; when it fires the text is linted (the problem list, the
  marks in the gutter, the tinted lines) and, unless it does not parse, loaded into the
  preview. A text that does not parse or load leaves the preview on the last version that
  worked (TTbPreviewFrame.LoadDocument).

  The window's own look is the tool's theme on TyDefaultController ("View > Editor
  appearance"); the preview is on a controller of its own. The SynEdit is the one non-Ty
  control (the library has no code editor); its colours come from the tool's theme.

  Every question the window asks goes through Ask, and the tests answer it
  (PromptAnswerForTest) -- nothing in a test path shows a modal window. Save As in a test
  takes SaveAsNameForTest, and the settings file SettingsFileForTest. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Forms, Controls, Graphics, Menus, ExtCtrls, Dialogs,
  SynEdit, SynEditTypes, SynEditMarks, SynEditMiscClasses,
  tyControls.Controller, tyControls.Form, tyControls.FormSurface, tyControls.Menu,
  tyControls.StatusBar, tyControls.ToolWindows, tyControls.ListBox, tyControls.Panel,
  tyControls.Splitter, tyControls.Icons.Lucide, tyControls.Dialogs.FileDialog,
  tyControls.ThemeLint, tyControls.Design.CssEditKit,
  tbdocument, tbsettings, tbproblems, tbpreview, tbeditorlook;

resourcestring
  rsTbTitle = '%s%s - Theme Builder';
  rsTbUntitled = 'Untitled';
  rsTbSaveChanges = 'Save the changes to %s?';
  rsTbOpenFailed = 'Could not open %s: %s';
  rsTbSaveFailed = 'Could not save %s: %s';
  rsTbSaved = 'Saved.';
  rsTbRegenerate = 'Saved. This theme is compiled into the library: run scripts/%s.';
  rsTbConverted = 'Read as %s; it will be saved as UTF-8.';
  rsTbPreviewKept = 'The preview kept the last version that worked: %s';
  rsTbParseKept = 'Not loaded: the preview shows the last version that worked.';
  rsTbNoProblems = 'No problems';
  rsTbLineCol = 'Ln %d, Col %d';
  rsTbFilter = 'Theme files (*.tycss)|*.tycss|All files|*';
  rsTbReload = 'The file %s was changed by another program. Reload it?';
  rsTbReloadLoses = 'Your unsaved changes will be lost.';

type
  TTbMainForm = class(TTyForm)
    Surface: TTyFormSurface;
    Bar: TTyTitleBar;
    MainMenuBar: TTyMenuBar;
    Status: TTyStatusBar;
    SideBar: TTyToolWindowBar;
    ProblemsWin: TTyToolWindow;
    ProblemsList: TTyListBox;
    PreviewHost: TTyPanel;
    PreviewSplitter: TTySplitter;
    Editor: TSynEdit;
    Icons: TTyLucideImageList;
    GutterIcons: TTyLucideImageList;
    MainMenu1: TMainMenu;
    MnuFile: TMenuItem;
    MnuNew: TMenuItem;
    MnuNewMinimal: TMenuItem;
    MnuNewSep: TMenuItem;
    MnuOpen: TMenuItem;
    MnuRecent: TMenuItem;
    MnuSave: TMenuItem;
    MnuSaveAs: TMenuItem;
    MnuFileSep: TMenuItem;
    MnuExit: TMenuItem;
    MnuView: TMenuItem;
    MnuAppearance: TMenuItem;
    MnuEditorDark: TMenuItem;
    MnuViewSep: TMenuItem;
    MnuProblems: TMenuItem;
    DlgOpen: TTyOpenDialog;
    DlgSave: TTySaveDialog;
    RefreshTimer: TTimer;
    WatchTimer: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure EditorChange(Sender: TObject);
    procedure EditorStatusChange(Sender: TObject; Changes: TSynStatusChanges);
    procedure EditorSpecialLineMarkup(Sender: TObject; Line: Integer;
      var Special: Boolean; Markup: TSynSelectedColor);
    procedure ProblemsListDblClick(Sender: TObject);
    procedure RefreshTimerTimer(Sender: TObject);
    procedure WatchTimerTimer(Sender: TObject);
    procedure MnuNewMinimalClick(Sender: TObject);
    procedure MnuOpenClick(Sender: TObject);
    procedure MnuSaveClick(Sender: TObject);
    procedure MnuSaveAsClick(Sender: TObject);
    procedure MnuExitClick(Sender: TObject);
    procedure MnuEditorDarkClick(Sender: TObject);
    procedure MnuProblemsClick(Sender: TObject);
  private
    FDoc: TTbDocument;
    FKit: TTyCssEditKit;
    FPreview: TTbPreviewFrame;
    FProblems: TTbProblems;
    FLint: TTbProblems;                { what the last refresh's lint found }
    FLoadError: string;                { the load the last refresh was refused, '' = none }
    FParseFailed: Boolean;             { the last refresh did not parse: nothing was loaded }
    FSettings: TTbSettings;
    FBaseVars: TStringList;
    FLook: TTbEditorColors;
    FLineSeverity: TStringList;        { line number -> Objects = 1 error / 2 warning }
    FProblemMarks: TFPList;            { the gutter marks ShowProblems placed }
    FAskCount: Integer;
    FLastAsk: string;
    FLastAskType: TMsgDlgType;
    FPrompting: Boolean;
    FPendingOpen: string;
    procedure OpenPending(Data: PtrInt);
    procedure MnuNewBuiltinClick(Sender: TObject);
    procedure MnuRecentClick(Sender: TObject);
    procedure MnuAppearanceClick(Sender: TObject);
    procedure PreviewChanged(Sender: TObject);
    procedure ToolThemeChanged(Sender: TObject);
    procedure ReloadKeepingCaret;
    procedure RebuildRecentMenu;
    procedure LoadEditor(const AText: string);
    function ConfirmDiscard: Boolean;
    procedure SaveSettings;
    function SaveAs: Boolean;
    procedure UpdateTitle;
    procedure UpdateStatusPosition;
    procedure ClampToEditor(var AList: TTbProblems);
    procedure BuildProblems;
    procedure ShowProblems;
    procedure ClearProblemMarks;
    procedure SetStatus(const AText: string);
    function DisplayName: string;
    function Ask(const AMsg: string; AButtons: TMsgDlgButtons;
      AType: TMsgDlgType = mtConfirmation): TModalResult;
  public
    class var PromptAnswerForTest: TModalResult;   { FOR THE TESTS: mrNone = really ask }
    class var SaveAsNameForTest: string;           { FOR THE TESTS }
    class var SettingsFileForTest: string;         { FOR THE TESTS }
    procedure RefreshNow;                          { lint + preview + problem list, now }
    procedure NewMinimal;
    procedure NewFromBuiltin(const AName: string);
    function OpenFile(const AFileName: string): Boolean;
    function SaveTo(const AFileName: string): Boolean;
    function SaveDocument: Boolean;                { Save As when untitled }
    procedure CheckDiskNow;                        { what the watch timer does }
    procedure JumpToProblem(AIndex: Integer);
    procedure SetEditorAppearance(const ATheme: string; ADark: Boolean);
    { FOR THE TESTS: how many times Ask answered from PromptAnswerForTest, and the last
      message it was given }
    property AskCount: Integer read FAskCount;
    property LastAsk: string read FLastAsk;
    property LastAskType: TMsgDlgType read FLastAskType;
    property Look: TTbEditorColors read FLook;
    property Doc: TTbDocument read FDoc;
    property Kit: TTyCssEditKit read FKit;
    property Preview: TTbPreviewFrame read FPreview;
    property Problems: TTbProblems read FProblems;
    property Settings: TTbSettings read FSettings;
  end;

var
  TbMainForm: TTbMainForm;

implementation

{$R *.lfm}

uses
  Math, tyControls.BuiltinThemes, tyControls.Dialogs, tbtemplates;

{ ---- create / destroy ---- }

procedure TTbMainForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  i: Integer;
  item: TMenuItem;
  err, ini: string;
begin
  TyRegisterBuiltinThemes;
  if SettingsFileForTest <> '' then
    ini := SettingsFileForTest
  else
    ini := TbDefaultSettingsFile;
  FSettings := TTbSettings.Create(ini);
  FSettings.Load;
  FDoc := TTbDocument.Create;
  FBaseVars := TStringList.Create;
  TbBaseVarNames(FBaseVars);
  FLineSeverity := TStringList.Create;
  FProblemMarks := TFPList.Create;
  { the problem marks carry their own image list (ShowProblems); SynEdit's bookmarks keep
    theirs -- sharing it made bookmark 0 and 1 show the error and warning signs }

  { the shared tycss setup; theme files keep their own alignment, so no tidying on line leave }
  FKit := TTyCssEditKit.Create(Self);
  FKit.FormatOnLineLeave := False;
  FKit.Attach(Editor, True);
  { and no trimming of trailing spaces on a line the caret leaves: a save writes back the
    bytes that were read, on the lines that were edited too }
  Editor.Options := Editor.Options - [eoTrimTrailingSpaces];

  FPreview := TTbPreviewFrame.Create(Self);
  FPreview.Parent := PreviewHost;
  FPreview.Align := alClient;
  FPreview.OnChanged := @PreviewChanged;

  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do
  begin
    item := TMenuItem.Create(Self);
    item.Caption := names[i];
    item.Hint := names[i];
    item.OnClick := @MnuNewBuiltinClick;
    MnuNew.Add(item);
    item := TMenuItem.Create(Self);
    item.Caption := names[i];
    item.Hint := names[i];
    item.RadioItem := True;
    item.GroupIndex := 1;
    item.OnClick := @MnuAppearanceClick;
    MnuAppearance.Add(item);
  end;
  RebuildRecentMenu;

  { the editor's colours follow the tool's theme; the listener goes in FormDestroy (the
    default controller outlives this window) }
  TyDefaultController.AddChangeListener(@ToolThemeChanged);
  SetEditorAppearance(FSettings.EditorTheme, FSettings.EditorDark);
  ToolThemeChanged(nil);
  FPreview.SetModern(FSettings.PreviewModern);
  NewMinimal;
  if FSettings.PreviewDark then
  begin
    FPreview.SetDark(True, err);
    RefreshNow;
  end;
end;

procedure TTbMainForm.FormDestroy(Sender: TObject);
begin
  Application.RemoveAsyncCalls(Self);
  TyDefaultController.RemoveChangeListener(@ToolThemeChanged);
  { the editor outlives this handler: it must not call back into a window taken apart }
  if FKit <> nil then
    FKit.Detach;
  Editor.OnChange := nil;
  Editor.OnStatusChange := nil;
  Editor.OnSpecialLineMarkup := nil;
  RefreshTimer.Enabled := False;
  WatchTimer.Enabled := False;
  ClearProblemMarks;
  FreeAndNil(FProblemMarks);
  FreeAndNil(FLineSeverity);
  FreeAndNil(FBaseVars);
  FreeAndNil(FDoc);
  FreeAndNil(FSettings);
end;

procedure TTbMainForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := ConfirmDiscard;
  if CanClose then
  begin
    FSettings.PreviewDark := FPreview.IsDark;
    FSettings.PreviewModern := FPreview.IsModern;
    SaveSettings;
  end;
end;

{ Best effort: a settings file that cannot be written (a read-only file, a full disk) must
  not keep the window open or lose the document being saved -- the settings are only the
  tool's own convenience. }
procedure TTbMainForm.SaveSettings;
begin
  try
    FSettings.Save;
  except
    { the next start begins from the defaults or the last file that was written }
  end;
end;

{ ---- asking ---- }

{ AType: a question is mtConfirmation; a failure to open or save is reported as mtError }
function TTbMainForm.Ask(const AMsg: string; AButtons: TMsgDlgButtons;
  AType: TMsgDlgType): TModalResult;
begin
  FLastAsk := AMsg;
  FLastAskType := AType;
  if PromptAnswerForTest <> mrNone then
  begin
    Inc(FAskCount);
    Exit(PromptAnswerForTest);
  end;
  Result := TyMessageDlg(AMsg, AType, AButtons, 0);
end;

function TTbMainForm.ConfirmDiscard: Boolean;
begin
  Result := True;
  if not Editor.Modified then Exit;
  case Ask(Format(rsTbSaveChanges, [DisplayName]), [mbYes, mbNo, mbCancel]) of
    mrYes: Result := SaveDocument;
    mrNo: Result := True;
  else
    Result := False;
  end;
end;

{ ---- the document ---- }

function TTbMainForm.DisplayName: string;
begin
  if not FDoc.Untitled then
    Result := ExtractFileName(FDoc.FileName)
  else if FDoc.BasedOn <> '' then
    Result := rsTbUntitled + ' (' + FDoc.BasedOn + ')'
  else
    Result := rsTbUntitled;
end;

procedure TTbMainForm.UpdateTitle;
var
  mark: string;
begin
  if Editor.Modified then mark := '*' else mark := '';
  Bar.Caption := Format(rsTbTitle, [DisplayName, mark]);
  Caption := Bar.Caption;
end;

procedure TTbMainForm.SetStatus(const AText: string);
begin
  if Status.Panels.Count > 0 then
    Status.Panels[0].Text := AText;
end;

procedure TTbMainForm.UpdateStatusPosition;
var
  enc: string;
begin
  if (FDoc = nil) or (Status.Panels.Count < 3) then Exit;
  Status.Panels[1].Text := Format(rsTbLineCol, [Editor.LogicalCaretXY.Y, Editor.LogicalCaretXY.X]);
  if FDoc.HasBom then enc := 'UTF-8 BOM' else enc := 'UTF-8';
  Status.Panels[2].Text := TbLineEndingName(FDoc.LineEnding) + ' · ' + enc;
end;

procedure TTbMainForm.LoadEditor(const AText: string);
begin
  { a new or opened document replaces the whole text: nothing to undo into }
  Editor.Lines.Text := AText;
  Editor.Modified := False;
  Editor.ClearUndo;
  Editor.CaretXY := Point(1, 1);
  UpdateTitle;
  UpdateStatusPosition;
  RefreshNow;
end;

procedure TTbMainForm.NewMinimal;
begin
  if not ConfirmDiscard then Exit;
  FDoc.NewUntitled(TbMinimalTemplate, '');
  LoadEditor(FDoc.EditorText);
end;

procedure TTbMainForm.NewFromBuiltin(const AName: string);
var
  css: string;
begin
  css := TbFromBuiltin(AName);
  if css = '' then Exit;
  if not ConfirmDiscard then Exit;
  FDoc.NewUntitled(css, AName);
  LoadEditor(FDoc.EditorText);
end;

function TTbMainForm.OpenFile(const AFileName: string): Boolean;
begin
  Result := False;
  if not ConfirmDiscard then Exit;
  try
    FDoc.LoadFromFile(AFileName);
  except
    on E: Exception do
    begin
      Ask(Format(rsTbOpenFailed, [AFileName, E.Message]), [mbOK], mtError);
      { only a file that is gone leaves the list: one another program holds open, or a
        share that is not there right now, is still the user's file }
      if not FileExists(AFileName) then
      begin
        FSettings.RemoveRecent(AFileName);
        SaveSettings;
        RebuildRecentMenu;
      end;
      Exit(False);
    end;
  end;
  FSettings.AddRecent(FDoc.FileName);
  SaveSettings;   { the recent list outlives a crash of this session }
  RebuildRecentMenu;
  LoadEditor(FDoc.EditorText);
  if FDoc.ConvertedFrom <> '' then
  begin
    Editor.Modified := True;
    UpdateTitle;
    SetStatus(Format(rsTbConverted, [FDoc.ConvertedFrom]));
  end;
  Result := True;
end;

function TTbMainForm.SaveTo(const AFileName: string): Boolean;
var
  regen: string;
begin
  try
    FDoc.SaveToFile(AFileName, Editor.Lines);
  except
    on E: Exception do
    begin
      Ask(Format(rsTbSaveFailed, [AFileName, E.Message]), [mbOK], mtError);
      Exit(False);
    end;
  end;
  Editor.Modified := False;
  FSettings.AddRecent(FDoc.FileName);
  SaveSettings;
  RebuildRecentMenu;
  UpdateTitle;
  UpdateStatusPosition;
  RefreshNow;   { the folder may have changed: url() resolves again }
  regen := FDoc.RegenerateHint;
  if regen <> '' then
    SetStatus(Format(rsTbRegenerate, [regen]))
  else
    SetStatus(rsTbSaved);
  Result := True;
end;

function TTbMainForm.SaveAs: Boolean;
var
  fname: string;
begin
  if SaveAsNameForTest <> '' then
    fname := SaveAsNameForTest
  else
  begin
    DlgSave.Filter := rsTbFilter;
    DlgSave.DefaultExt := 'tycss';
    if FDoc.Untitled then
    begin
      if FDoc.BasedOn <> '' then
        DlgSave.FileName := FDoc.BasedOn + '.tycss'
      else
        DlgSave.FileName := 'theme.tycss';
    end
    else
      DlgSave.FileName := FDoc.FileName;
    if not DlgSave.Execute then
      Exit(False);
    fname := DlgSave.FileName;
  end;
  Result := SaveTo(fname);
end;

function TTbMainForm.SaveDocument: Boolean;
begin
  if FDoc.Untitled then
    Result := SaveAs
  else
    Result := SaveTo(FDoc.FileName);
end;

procedure TTbMainForm.RebuildRecentMenu;
var
  i: Integer;
  item: TMenuItem;
begin
  MnuRecent.Clear;
  for i := 0 to FSettings.Recent.Count - 1 do
  begin
    item := TMenuItem.Create(Self);
    { a menu caption takes & as the accelerator mark: a path is shown as it is }
    item.Caption := StringReplace(FSettings.Recent[i], '&', '&&', [rfReplaceAll]);
    item.Tag := i;
    item.OnClick := @MnuRecentClick;
    MnuRecent.Add(item);
  end;
  MnuRecent.Enabled := FSettings.Recent.Count > 0;
end;

{ ---- refreshing ---- }

procedure TTbMainForm.EditorChange(Sender: TObject);
begin
  UpdateTitle;
  RefreshTimer.Enabled := False;   { restart: 300 ms after the last keystroke }
  RefreshTimer.Enabled := True;
end;

procedure TTbMainForm.RefreshTimerTimer(Sender: TObject);
begin
  RefreshNow;
end;

procedure TTbMainForm.RefreshNow;
var
  css, err: string;
begin
  RefreshTimer.Enabled := False;
  css := Editor.Lines.Text;
  FLint := TbCollectProblems(css, FDoc.BaseDir, FDoc.Untitled, FBaseVars);
  ClampToEditor(FLint);
  FParseFailed := TbHasParseError(FLint);
  FLoadError := '';
  if not FParseFailed then
    if not FPreview.LoadDocument(css, FDoc.BaseDir, err) then
      FLoadError := err;
  BuildProblems;
end;

{ Lines.Text ends with a line break the editor does not show as a line: an error at the end
  of the text (a rule left open) is placed on the line after the last one. Such a position,
  and a column past a line's end, is moved to the end of the text the editor has -- where
  the caret can go and the gutter can mark it. }
procedure TTbMainForm.ClampToEditor(var AList: TTbProblems);
var
  i, n: Integer;
begin
  n := Editor.Lines.Count;
  for i := 0 to High(AList) do
  begin
    if AList[i].Line <= 0 then Continue;
    if n = 0 then
    begin
      AList[i].Line := 1;
      AList[i].Col := 1;
      Continue;
    end;
    if AList[i].Line > n then
    begin
      AList[i].Line := n;
      AList[i].Col := Length(Editor.Lines[n - 1]) + 1;
    end
    else if AList[i].Col > Length(Editor.Lines[AList[i].Line - 1]) + 1 then
      AList[i].Col := Length(Editor.Lines[AList[i].Line - 1]) + 1;
  end;
end;

{ The list from what the last refresh found plus what the preview says now: a switch the
  preview refused arrives here without a reload (PreviewChanged) -- reloading would count
  as a good load and forget the refusal. While the text does not parse nothing was loaded,
  and a refusal about the version still shown is not about what is being written. }
procedure TTbMainForm.BuildProblems;
begin
  FProblems := Copy(FLint);
  if FLoadError <> '' then
    TbAddProblem(FProblems, 0, 0, tlsError, tpoLoad, Format(rsTbPreviewKept, [FLoadError]));
  if (not FParseFailed) and (FPreview.ModeError <> '') then
    TbAddProblem(FProblems, 0, 0, tlsError, tpoLoad, FPreview.ModeError);
  ShowProblems;
end;

procedure TTbMainForm.ClearProblemMarks;
var
  i: Integer;
begin
  if FProblemMarks = nil then Exit;
  for i := FProblemMarks.Count - 1 downto 0 do
    TSynEditMark(FProblemMarks[i]).Free;
  FProblemMarks.Clear;
end;

procedure TTbMainForm.ShowProblems;
var
  i, k, sev: Integer;
  mark: TSynEditMark;
  key: string;
  errors: Integer;
begin
  ProblemsList.Items.BeginUpdate;
  try
    ProblemsList.Items.Clear;
    for i := 0 to High(FProblems) do
      ProblemsList.Items.Add(TbProblemCaption(FProblems[i]));
  finally
    ProblemsList.Items.EndUpdate;
  end;
  errors := TbErrorCount(FProblems);
  ProblemsWin.BadgeValue := errors;
  ProblemsWin.ShowBadge := errors > 0;

  { one mark per line, the worse of what is on it }
  FLineSeverity.Clear;
  for i := 0 to High(FProblems) do
    if FProblems[i].Line > 0 then
    begin
      if FProblems[i].Severity = tlsError then sev := 1 else sev := 2;
      key := IntToStr(FProblems[i].Line);
      k := FLineSeverity.IndexOf(key);
      if k < 0 then
        FLineSeverity.AddObject(key, TObject(PtrInt(sev)))
      else if sev < PtrInt(FLineSeverity.Objects[k]) then
        FLineSeverity.Objects[k] := TObject(PtrInt(sev));
    end;
  ClearProblemMarks;
  for i := 0 to FLineSeverity.Count - 1 do
  begin
    mark := TSynEditMark.Create(Editor);
    mark.Line := StrToInt(FLineSeverity[i]);
    mark.ImageList := GutterIcons;
    mark.ImageIndex := PtrInt(FLineSeverity.Objects[i]) - 1;   { 0 error, 1 warning }
    mark.Visible := True;
    Editor.Marks.Add(mark);
    FProblemMarks.Add(mark);
  end;
  Editor.Invalidate;

  if Length(FProblems) = 0 then
    SetStatus(rsTbNoProblems)
  else if TbHasParseError(FProblems) then
    SetStatus(rsTbParseKept)
  else
    SetStatus('');
end;

procedure TTbMainForm.EditorSpecialLineMarkup(Sender: TObject; Line: Integer;
  var Special: Boolean; Markup: TSynSelectedColor);
var
  k: Integer;
begin
  if FLineSeverity = nil then Exit;
  k := FLineSeverity.IndexOf(IntToStr(Line));
  if k < 0 then Exit;
  Special := True;
  if PtrInt(FLineSeverity.Objects[k]) = 1 then
    Markup.Background := FLook.ErrorLine
  else
    Markup.Background := FLook.WarningLine;
end;

procedure TTbMainForm.JumpToProblem(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(FProblems)) then Exit;
  if FProblems[AIndex].Line <= 0 then Exit;
  { the problem's column counts bytes, as SynEdit's LOGICAL column does }
  Editor.LogicalCaretXY := Point(Max(1, FProblems[AIndex].Col), FProblems[AIndex].Line);
  Editor.EnsureCursorPosVisible;
  if Editor.CanSetFocus then
    Editor.SetFocus;
end;

procedure TTbMainForm.ProblemsListDblClick(Sender: TObject);
begin
  JumpToProblem(ProblemsList.ItemIndex);
end;

procedure TTbMainForm.EditorStatusChange(Sender: TObject; Changes: TSynStatusChanges);
begin
  UpdateStatusPosition;
end;

{ a switch on the preview's strip was used: the document is where it was, only what the
  preview says about it (a refused mode) may have changed }
procedure TTbMainForm.PreviewChanged(Sender: TObject);
begin
  BuildProblems;
end;

{ ---- the file on disk ---- }

procedure TTbMainForm.WatchTimerTimer(Sender: TObject);
begin
  CheckDiskNow;
end;

procedure TTbMainForm.CheckDiskNow;
var
  msg: string;
begin
  if FPrompting or (Application.ModalLevel > 0) then Exit;
  if not FDoc.DiskChanged then Exit;          { takes the stamp again: asked once per change }
  msg := Format(rsTbReload, [FDoc.FileName]);
  if Editor.Modified then
    msg := msg + LineEnding + rsTbReloadLoses;
  FPrompting := True;
  try
    if Ask(msg, [mbYes, mbNo]) = mrYes then
      ReloadKeepingCaret;
  finally
    FPrompting := False;
  end;
end;

{ Reload after the question above: no second "save the changes?" }
procedure TTbMainForm.ReloadKeepingCaret;
var
  y, topRow: Integer;
  fname: string;
begin
  y := Editor.CaretY;
  topRow := Editor.TopLine;
  fname := FDoc.FileName;
  try
    FDoc.LoadFromFile(fname);
  except
    on E: Exception do
    begin
      Ask(Format(rsTbOpenFailed, [fname, E.Message]), [mbOK], mtError);
      Exit;
    end;
  end;
  LoadEditor(FDoc.EditorText);
  if Editor.Lines.Count > 0 then
  begin
    Editor.CaretY := Max(1, Min(y, Editor.Lines.Count));
    Editor.TopLine := Max(1, Min(topRow, Editor.Lines.Count));
  end;
end;

{ ---- the editor's look ---- }

procedure TTbMainForm.SetEditorAppearance(const ATheme: string; ADark: Boolean);
var
  i: Integer;
begin
  { the tool's own theme, on the default controller; the colours follow through
    ToolThemeChanged }
  TyDefaultController.ThemeName := ATheme;
  if ADark then
    TyDefaultController.Mode := 'dark'
  else
    TyDefaultController.Mode := 'light';
  ApplyChromeTheme(TyDefaultController);
  for i := 0 to MnuAppearance.Count - 1 do
    MnuAppearance.Items[i].Checked := SameText(MnuAppearance.Items[i].Hint, ATheme);
  MnuEditorDark.Checked := ADark;
  FSettings.EditorTheme := ATheme;
  FSettings.EditorDark := ADark;
end;

procedure TTbMainForm.ToolThemeChanged(Sender: TObject);
begin
  if (Editor = nil) or (FKit = nil) then Exit;
  FLook := TbEditorColors(TyDefaultController);
  TbApplyEditorColors(Editor, FKit.Highlighter, FLook);
  Editor.Invalidate;
end;

{ ---- menus ---- }

procedure TTbMainForm.MnuNewMinimalClick(Sender: TObject);
begin
  NewMinimal;
end;

procedure TTbMainForm.MnuNewBuiltinClick(Sender: TObject);
begin
  NewFromBuiltin((Sender as TMenuItem).Hint);
end;

procedure TTbMainForm.MnuOpenClick(Sender: TObject);
begin
  DlgOpen.Filter := rsTbFilter;
  if DlgOpen.Execute then
    OpenFile(DlgOpen.FileName);
end;

procedure TTbMainForm.MnuRecentClick(Sender: TObject);
var
  i: Integer;
begin
  i := (Sender as TMenuItem).Tag;
  if (i < 0) or (i >= FSettings.Recent.Count) then Exit;
  { opening rebuilds this very menu: do it after the click has finished with its item }
  FPendingOpen := FSettings.Recent[i];
  Application.QueueAsyncCall(@OpenPending, 0);
end;

procedure TTbMainForm.OpenPending(Data: PtrInt);
var
  f: string;
begin
  f := FPendingOpen;
  FPendingOpen := '';
  if f <> '' then
    OpenFile(f);
end;

procedure TTbMainForm.MnuSaveClick(Sender: TObject);
begin
  SaveDocument;
end;

procedure TTbMainForm.MnuSaveAsClick(Sender: TObject);
begin
  SaveAs;
end;

procedure TTbMainForm.MnuExitClick(Sender: TObject);
begin
  Close;
end;

procedure TTbMainForm.MnuAppearanceClick(Sender: TObject);
begin
  SetEditorAppearance((Sender as TMenuItem).Hint, MnuEditorDark.Checked);
end;

procedure TTbMainForm.MnuEditorDarkClick(Sender: TObject);
begin
  SetEditorAppearance(FSettings.EditorTheme, MnuEditorDark.Checked);
end;

procedure TTbMainForm.MnuProblemsClick(Sender: TObject);
begin
  SideBar.Collapsed := not SideBar.Collapsed;
end;

end.
