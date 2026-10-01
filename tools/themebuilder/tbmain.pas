unit tbmain;
{ The theme builder's main window: a side-bar workbench (the Seeds, Problems and AI pages),
  the .tycss editor in the middle, the preview on the right.

  Typing restarts a 300 ms timer; when it fires the text is linted (the problem list, the
  marks in the gutter, the tinted lines) and, unless it does not parse, loaded into the
  preview. A text that does not parse or load leaves the preview on the last version that
  worked (TTbPreviewFrame.LoadDocument).

  The window's own look is the tool's theme on TyDefaultController ("View > Editor
  appearance"); the preview is on a controller of its own. The SynEdit is the one non-Ty
  control (the library has no code editor); its colours come from the tool's theme.

  Every change that is not typed -- a seed from the seeds page, a rule added by Ctrl+click in
  the preview or from the coverage check -- arrives as a set of edits worked out on the
  text as it was (tbcssscan): ApplyEdits checks the editor still has that text, applies them
  back to front inside one undo block (Ctrl+Z takes the whole change back at once) and
  refreshes, and the refresh brings the seeds page up to date (UpdateFrom). Ctrl+click goes
  to the rule for the control's typeKey and variant (tbrules); clicking the same control
  again goes to the next rule of that name, round and round.

  The AI page (tbaiframe) hands over a version the checks let through; the comparison window
  (BuildCompareForm) shows it beside the editor's text, can try it in the preview
  (CompareTrial -- while a trial is on, refreshing does not load the editor's text into the
  preview) and on Accept it goes into the editor as one edit over the differing lines, one
  undo step (AcceptCandidate, ApplyEdits). If the editor changed after the request went out,
  accepting asks first. A new or another opened document starts a new AI conversation.

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
  tbdocument, tbsettings, tbproblems, tbpreview, tbeditorlook, tbcssscan, tbseedsframe,
  tbcoverageform, tbexportform, tbsnippetsform, tbaisettings, tbaisession, tbaiframe,
  tbcompareform, tbaisettingsform;

const
  cTbPreviewKeptEn = 'The preview kept the last version that worked: %s';  { for the AI }

resourcestring
  rsTbTitle = '%s%s - Theme Builder';
  rsTbUntitled = 'Untitled';
  rsTbSaveChanges = 'Save the changes to %s?';
  rsTbOpenFailed = 'Could not open %s: %s';
  rsTbSaveFailed = 'Could not save %s: %s';
  rsTbSaved = 'Saved.';
  rsTbRegenerate = 'Saved. This theme is compiled into the library: run scripts/%s.';
  rsTbConverted = 'Read as %s; it will be saved as UTF-8.';
  rsTbPreviewKept = cTbPreviewKeptEn;
  rsTbParseKept = 'Not loaded: the preview shows the last version that worked.';
  rsTbNoProblems = 'No problems';
  rsTbLineCol = 'Ln %d, Col %d';
  rsTbFilter = 'Theme files (*.tycss)|*.tycss|All files|*';
  rsTbReload = 'The file %s was changed by another program. Reload it?';
  rsTbReloadLoses = 'Your unsaved changes will be lost.';
  rsTbExported = 'Exported to %s.';
  rsTbAiEditedSince = 'The editor changed after this was generated. Accepting replaces those changes too. Accept?';
  rsTbAiAccepted = 'Accepted the AI''s version. Ctrl+Z undoes it.';

type
  TTbMainForm = class(TTyForm)
    Surface: TTyFormSurface;
    Bar: TTyTitleBar;
    MainMenuBar: TTyMenuBar;
    Status: TTyStatusBar;
    SideBar: TTyToolWindowBar;
    SeedsWin: TTyToolWindow;
    SeedsHost: TTyPanel;
    ProblemsWin: TTyToolWindow;
    ProblemsList: TTyListBox;
    AiWin: TTyToolWindow;
    AiHost: TTyPanel;
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
    MnuExportSep: TMenuItem;
    MnuExport: TMenuItem;
    MnuSnippets: TMenuItem;
    MnuFileSep: TMenuItem;
    MnuExit: TMenuItem;
    MnuView: TMenuItem;
    MnuAppearance: TMenuItem;
    MnuEditorDark: TMenuItem;
    MnuViewSep: TMenuItem;
    MnuSeeds: TMenuItem;
    MnuProblems: TMenuItem;
    MnuAi: TMenuItem;
    MnuViewSep2: TMenuItem;
    MnuCoverage: TMenuItem;
    MnuAiSettings: TMenuItem;
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
    procedure MnuSeedsClick(Sender: TObject);
    procedure MnuCoverageClick(Sender: TObject);
    procedure MnuExportClick(Sender: TObject);
    procedure MnuSnippetsClick(Sender: TObject);
    procedure MnuAiClick(Sender: TObject);
    procedure MnuAiSettingsClick(Sender: TObject);
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
    FSeeds: TTbSeedsFrame;
    FJumpKey: string;                  { the rule Ctrl+click went to last (lower case) }
    FJumpIndex: Integer;               { which of its selectors }
    FMergeKey: string;                 { the kind of the last change ApplyEdits may fold into }
    FMergeBefore, FMergeAfter: string; { the text before it, and the text it left }
    FAi: TTbAiFrame;
    FAiSettings: TTbAiSettings;
    FTrialText: string;                { the version the comparison window tries }
    function AiDocument: TTbAiDocument;
    procedure AiCandidate(Sender: TObject);
    procedure AiSettingsClick(Sender: TObject);
    function RunModal(AForm: TCustomForm): TModalResult;
    procedure OpenPending(Data: PtrInt);
    function SeedsEdits(Sender: TObject; const AText: string; const AEdits: TTbTextEdits;
      const AMergeKey: string): Boolean;
    procedure SeedsWinShow(Sender: TObject);
    procedure PutEdits(const AText: string; const AEdits: TTbTextEdits);
    procedure SeedsSync(Sender: TObject);
    procedure PreviewPick(Sender: TObject; const ATypeKey, AStyleClass: string);
    procedure ShowSidePage(AWin: TTyToolWindow);
    function AskFor(const AMsg: string; AButtons: TMsgDlgButtons): TModalResult;
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
    { FOR THE TESTS: called first thing whenever a window hears the tool's theme change
      (before it touches itself), so a test can tell a freed window still listening }
    class var ToolThemeChangedForTest: TNotifyEvent;
    { FOR THE TESTS: called with the comparison or AI settings window instead of showing it;
      its ModalResult afterwards is the answer }
    class var ShowModalForTest: TNotifyEvent;
    procedure RefreshNow;                          { lint + preview + problem list, now }
    procedure NewMinimal;
    procedure NewFromBuiltin(const AName: string);
    function OpenFile(const AFileName: string): Boolean;
    function SaveTo(const AFileName: string): Boolean;
    function SaveDocument: Boolean;                { Save As when untitled }
    procedure CheckDiskNow;                        { what the watch timer does }
    procedure JumpToProblem(AIndex: Integer);
    procedure SetEditorAppearance(const ATheme: string; ADark: Boolean);
    { the edits (worked out on AText) as ONE undo step, then a refresh. False when the editor
      no longer has AText: offsets into another text mean nothing. AMergeKey: a change of
      the same kind right after the last one (nothing else in between) joins its undo step
      -- the radius spin boxes, step after step }
    function ApplyEdits(const AText: string; const AEdits: TTbTextEdits;
      const AMergeKey: string = ''): Boolean;
    { go to the rule for ATypeKey and a class of AStyleClass (the next one, when it is the
      same control again), or add one: a variant rule empty at the end, a plain rule as a
      copy of the base's rules for the typeKey (tbrules: an empty one would take the base
      layer away and leave the control unstyled) }
    procedure JumpToRule(const ATypeKey, AStyleClass: string);
    { the coverage check's double click: to the document's first rule for ATypeKey whatever
      its variant and state (the next one, the same key again) -- an entry of the first list
      is there because the document has one; only a typeKey with none gets a rule added
      (JumpToRule) }
    procedure JumpToTypeKey(const ATypeKey: string);
    function BuildCoverageForm: TTbCoverageForm;     { filled, not shown }
    function BuildExportForm: TTbExportForm;         { prepared, not shown }
    function BuildSnippetsForm: TTbSnippetsForm;     { prepared, not shown }
    function EntryBytes: string;                     { what Save would write, without a BOM }
    { the comparison of the AI's last version, prepared, not shown }
    function BuildCompareForm: TTbCompareForm;
    { the AI's version into the editor: one edit over the lines that differ, one undo step;
      asks first when the editor no longer has ABase }
    function AcceptCandidate(const ABase, ACandidate: string): Boolean;
    function BuildAiSettingsForm: TTbAiSettingsForm;   { prepared, not shown }
    { the comparison window's "Try it in the preview" }
    procedure CompareTrial(Sender: TObject; AOn: Boolean; out AError: string);
    function SnippetName: string;
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
    property Seeds: TTbSeedsFrame read FSeeds;
    property Ai: TTbAiFrame read FAi;
    property AiSettings: TTbAiSettings read FAiSettings;
  end;

var
  TbMainForm: TTbMainForm;

implementation

{$R *.lfm}

uses
  Math, StrUtils, tyControls.BuiltinThemes, tyControls.Dialogs, tbtemplates, tbrules,
  tbcoverage, tbsnippets, tbdiff;

{ ---- create / destroy ---- }

procedure TTbMainForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  i: Integer;
  item: TMenuItem;
  err, ini, aiIni, aiKeys: string;
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
  FPreview.OnPick := @PreviewPick;

  { the seeds page: its changes come back as edits, its questions go through Ask }
  FSeeds := TTbSeedsFrame.Create(Self);
  FSeeds.Parent := SeedsHost;
  FSeeds.Align := alClient;
  FSeeds.OnEdits := @SeedsEdits;
  FSeeds.OnAsk := @AskFor;
  FSeeds.OnSync := @SeedsSync;
  SeedsWin.OnShow := @SeedsWinShow;

  { the AI page: its settings sit next to the tool's own (themebuilder-ai.ini) }
  TbAiFilesFor(FSettings.FileName, aiIni, aiKeys);
  FAiSettings := TTbAiSettings.Create(aiIni, aiKeys);
  FAiSettings.Load;
  FAi := TTbAiFrame.Create(Self);
  FAi.Parent := AiHost;
  FAi.Align := alClient;
  FAi.OnGetDocument := @AiDocument;
  FAi.OnCandidate := @AiCandidate;
  FAi.OnSettings := @AiSettingsClick;
  FAi.Setup(FAiSettings, FBaseVars);

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
  { a generation still running stops; nothing of the AI page calls back any more }
  if FAi <> nil then
  begin
    FAi.Session.Stop;
    FAi.OnGetDocument := nil;
    FAi.OnCandidate := nil;
    FAi.OnSettings := nil;
  end;
  if FPreview <> nil then
    FPreview.EndTrial;
  { the frames outlive this handler: nothing of theirs may call back into the window }
  SeedsWin.OnShow := nil;
  if FSeeds <> nil then
  begin
    FSeeds.OnEdits := nil;
    FSeeds.OnAsk := nil;
    FSeeds.OnSync := nil;
  end;
  if FPreview <> nil then
    FPreview.OnPick := nil;
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
  { the frame (a child of the window) is freed after this handler: it stops its session,
    and never reads the settings again }
  if FAi <> nil then
    FAi.Session.Backend := nil;
  FreeAndNil(FAiSettings);
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

{ Ask, in the shape the frames and dialogs ask in (TTbAskEvent): a question }
function TTbMainForm.AskFor(const AMsg: string; AButtons: TMsgDlgButtons): TModalResult;
begin
  Result := Ask(AMsg, AButtons);
end;

function TTbMainForm.ConfirmDiscard: Boolean;
begin
  Result := True;
  if FSeeds <> nil then
    FSeeds.FlushRadius;     { a spin box step still waiting is a change too }
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
  FMergeKey := '';
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
  if FAi <> nil then
    FAi.DocumentChanged(TbErrorCount(FProblems) > 0);
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
  if FAi <> nil then
    FAi.DocumentChanged(TbErrorCount(FProblems) > 0);
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
  { another document: a new conversation (a reload of the same one keeps it) }
  if FAi <> nil then
    FAi.DocumentChanged(TbErrorCount(FProblems) > 0);
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
  FSeeds.FlushRadius;       { a spin box step still waiting goes into what is saved }
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
  { while the comparison window tries the AI's version, the preview keeps showing it }
  if not FParseFailed and not FPreview.InTrial then
    if not FPreview.LoadDocument(css, FDoc.BaseDir, err) then
      FLoadError := err;
  { the seeds page follows the text; a text that does not parse leaves it disabled }
  if FSeeds <> nil then
    FSeeds.UpdateFrom(css, FDoc.BaseDir, FParseFailed);
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
    TbAddProblem(FProblems, 0, 0, tlsError, tpoLoad, Format(rsTbPreviewKept, [FLoadError]),
      Format(cTbPreviewKeptEn, [TbAsciiOr(FLoadError, 'the theme does not load')]));
  if (not FParseFailed) and (FPreview.ModeError <> '') then
    TbAddProblem(FProblems, 0, 0, tlsError, tpoLoad, FPreview.ModeError, FPreview.ModeErrorEn);
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
  if FAi <> nil then
    FAi.ProblemsChanged(errors > 0);
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

{ ---- edits from the seeds page, Ctrl+click and the coverage check ---- }

{ the one edit that turns ABefore into AAfter: what lies between their common start and
  their common end }
function DiffEdit(const ABefore, AAfter: string): TTbTextEdits;
var
  p, s, nb, na: Integer;
begin
  nb := Length(ABefore);
  na := Length(AAfter);
  p := 0;
  while (p < nb) and (p < na) and (ABefore[p + 1] = AAfter[p + 1]) do
    Inc(p);
  s := 0;
  while (s < nb - p) and (s < na - p) and (ABefore[nb - s] = AAfter[na - s]) do
    Inc(s);
  SetLength(Result, 1);
  Result[0] := TbEdit(p + 1, nb - s + 1, Copy(AAfter, p + 1, na - s - p));
end;

function TTbMainForm.ApplyEdits(const AText: string; const AEdits: TTbTextEdits;
  const AMergeKey: string): Boolean;
var
  target: string;
begin
  Result := False;
  { the edits were worked out on AText; on any other text their offsets mean nothing }
  if (Length(AEdits) = 0) or (Editor.Lines.Text <> AText) then Exit;
  { The same kind of change again, right after the last one (the editor has exactly what it
    left): the last one is undone and both go back in as one step, from where the first
    one started. Undo must land on that text -- if it does not, the step on top was not
    ours: it is redone, and this change is a step of its own. }
  if (AMergeKey <> '') and (AMergeKey = FMergeKey) and (AText = FMergeAfter) then
  begin
    target := TbApplyEdits(AText, AEdits);
    Editor.Undo;
    if Editor.Lines.Text = FMergeBefore then
    begin
      PutEdits(FMergeBefore, DiffEdit(FMergeBefore, target));
      FMergeAfter := Editor.Lines.Text;
      UpdateTitle;
      RefreshNow;
      Exit(True);
    end;
    Editor.Redo;
    if Editor.Lines.Text <> AText then
      Exit;          { the editor is not where the edits were worked out any more }
  end;
  PutEdits(AText, AEdits);
  if AMergeKey <> '' then
  begin
    FMergeKey := AMergeKey;
    FMergeBefore := AText;
    FMergeAfter := Editor.Lines.Text;
  end
  else
    FMergeKey := '';
  UpdateTitle;
  RefreshNow;
  Result := True;
end;

procedure TTbMainForm.PutEdits(const AText: string; const AEdits: TTbTextEdits);
var
  i, last, n: Integer;
  e: TTbTextEdit;
  tail: string;
  wasEmpty: Boolean;
begin
  { Lines.Text ends with a line break the editor has no line after (only a whole-text
    replacement reaches it): such an edit stops before it, and leaves its own final break.
    An editor with no line at all has no such break (Lines.Text is ''): what an edit at
    its end brings ends with a break Lines.Text adds by itself, so it goes too -- and
    SynEdit, inserting into no line, makes one empty line after what it inserts, which
    goes as well (in the same undo step). Either one kept is one empty line more. }
  last := TbEndInsertPos(AText);
  tail := Copy(AText, last, MaxInt);
  wasEmpty := Editor.Lines.Count = 0;
  Editor.BeginUndoBlock;
  try
    for i := High(AEdits) downto 0 do   { back to front: the earlier offsets stay good }
    begin
      e := AEdits[i];
      if e.Stop > last then
      begin
        e.Stop := last;
        if (tail <> '') and (Copy(e.Text, Length(e.Text) - Length(tail) + 1, MaxInt) = tail) then
          SetLength(e.Text, Length(e.Text) - Length(tail));
      end
      else if (tail = '') and (e.Stop = last) then
        SetLength(e.Text, TbEndInsertPos(e.Text) - 1);
      if e.Start > last then
        e.Start := last;
      Editor.SetTextBetweenPoints(TbOffsetToPoint(AText, e.Start), TbOffsetToPoint(AText, e.Stop),
        e.Text, [], scamAdjust);
    end;
    n := Editor.Lines.Count;
    if wasEmpty and (n > 1) and (Editor.Lines[n - 1] = '') then
      Editor.SetTextBetweenPoints(Point(Length(Editor.Lines[n - 2]) + 1, n - 1), Point(1, n), '',
        [], scamAdjust);
  finally
    Editor.EndUndoBlock;
  end;
end;

function TTbMainForm.SeedsEdits(Sender: TObject; const AText: string; const AEdits: TTbTextEdits;
  const AMergeKey: string): Boolean;
begin
  Result := ApplyEdits(AText, AEdits, AMergeKey);
end;

procedure TTbMainForm.SeedsWinShow(Sender: TObject);
begin
  if FSeeds <> nil then
    FSeeds.CatchUp;     { refreshes while it was hidden were only taken, not worked through }
end;

{ the seeds page is about to work out an edit: what it scanned must be what the editor has
  (a keystroke may be waiting on the refresh timer) }
procedure TTbMainForm.SeedsSync(Sender: TObject);
begin
  if RefreshTimer.Enabled or ((FSeeds <> nil) and (Editor.Lines.Text <> FSeeds.ScannedText)) then
    RefreshNow;
end;

{ 'primary ghost' -> ['primary', 'ghost'] }
function SplitClasses(const S: string): TStringArray;
var
  i, n: Integer;
begin
  n := WordCount(S, [' ', #9]);
  SetLength(Result, n);
  for i := 1 to n do
    Result[i - 1] := ExtractWord(i, S, [' ', #9]);
end;

{ some file AText @imports has a plain rule for ATypeKey: the user layer owns it already }
function ImportsHavePlainRule(const AText, ABaseDir, ATypeKey: string): Boolean;
var
  scans: TTbCssScans;
  i: Integer;
begin
  Result := False;
  scans := TbScanImports(AText, ABaseDir);
  try
    for i := 0 to High(scans) do
      if Length(TbFindRuleSelectors(scans[i], ATypeKey, '')) > 0 then
        Exit(True);
  finally
    TbFreeScans(scans);
  end;
end;

procedure TTbMainForm.JumpToRule(const ATypeKey, AStyleClass: string);
var
  scan: TTbCssScan;
  classes: TStringArray;
  hits: TTbOffsets;
  i, caret: Integer;
  variant, key, src: string;
  edits: TTbTextEdits;
begin
  if ATypeKey = '' then Exit;
  FSeeds.FlushRadius;
  src := Editor.Lines.Text;
  scan := TbScanCss(src);
  try
    classes := SplitClasses(AStyleClass);
    hits := nil;
    variant := '';
    { a control with several classes: the first one the document has a rule for }
    for i := 0 to High(classes) do
    begin
      hits := TbFindRuleSelectors(scan, ATypeKey, classes[i]);
      if Length(hits) > 0 then
      begin
        variant := classes[i];
        Break;
      end;
    end;
    if (Length(hits) = 0) and (Length(classes) = 0) then
      hits := TbFindRuleSelectors(scan, ATypeKey, '');
    if (Length(hits) = 0) and (Length(classes) > 0) then
      variant := classes[0];
    if Length(hits) > 0 then
    begin
      { the same control again: the next rule of that name, round and round }
      key := LowerCase(TbSelectorText(ATypeKey, variant));
      if key = FJumpKey then
        FJumpIndex := (FJumpIndex + 1) mod Length(hits)
      else
        FJumpIndex := 0;
      FJumpKey := key;
      Editor.LogicalCaretXY := TbOffsetToPoint(src, hits[FJumpIndex]);
    end
    else
    begin
      FJumpKey := '';
      { a plain rule takes the base layer's rules for the typeKey away (UserHasTypeKey):
        it starts as a copy of them, unless the theme already has one of its own (from an
        @import) and the base is gone anyway -- see tbrules }
      if (variant = '') and not FPreview.Controller.Model.PropertyCascade
         and not ImportsHavePlainRule(src, FDoc.BaseDir, ATypeKey) then
        edits := TbOwnRuleEdits(scan, TbDetectEol(src), ATypeKey, caret)
      else
        edits := TbNewRuleEdits(scan, TbDetectEol(src), ATypeKey, variant, caret);
      if ApplyEdits(src, edits) then
        Editor.LogicalCaretXY := TbOffsetToPoint(TbApplyEdits(src, edits), caret);
    end;
  finally
    scan.Free;
  end;
  Editor.EnsureCursorPosVisible;
  { a click in the sample window: the editor's window comes forward }
  if Showing and not Active then
    BringToFront;
  if Editor.CanSetFocus then
    Editor.SetFocus;
end;

procedure TTbMainForm.JumpToTypeKey(const ATypeKey: string);
var
  scan: TTbCssScan;
  hits: TTbOffsets;
  src, key: string;
begin
  if ATypeKey = '' then Exit;
  src := Editor.Lines.Text;
  scan := TbScanCss(src);
  try
    hits := TbFindTypeSelectors(scan, ATypeKey);
  finally
    scan.Free;
  end;
  if Length(hits) = 0 then
  begin
    JumpToRule(ATypeKey, '');
    Exit;
  end;
  key := '*' + LowerCase(ATypeKey);
  if key = FJumpKey then
    FJumpIndex := (FJumpIndex + 1) mod Length(hits)
  else
    FJumpIndex := 0;
  FJumpKey := key;
  Editor.LogicalCaretXY := TbOffsetToPoint(src, hits[FJumpIndex]);
  Editor.EnsureCursorPosVisible;
  if Editor.CanSetFocus then
    Editor.SetFocus;
end;

procedure TTbMainForm.PreviewPick(Sender: TObject; const ATypeKey, AStyleClass: string);
begin
  JumpToRule(ATypeKey, AStyleClass);
end;

{ ---- the dialogs ---- }

function TTbMainForm.BuildCoverageForm: TTbCoverageForm;
var
  docKeys, prevKeys, baseKeys, notShown, defKeys: TStringList;
  scan: TTbCssScan;

  function NewKeys: TStringList;
  begin
    Result := TStringList.Create;
    Result.CaseSensitive := False;
    Result.Sorted := True;
    Result.Duplicates := dupIgnore;
  end;

begin
  docKeys := NewKeys;
  prevKeys := NewKeys;
  baseKeys := NewKeys;
  notShown := TStringList.Create;
  defKeys := TStringList.Create;
  scan := TbScanCss(Editor.Lines.Text);
  try
    TbDocTypeKeys(scan, docKeys);
    FPreview.CollectTypeKeys(prevKeys);
    TbBaseTypeKeys(baseKeys);
    TbCoverageLists(docKeys, prevKeys, baseKeys, notShown, defKeys);
    Result := TTbCoverageForm.Create(nil);
    Result.Fill(notShown, defKeys, prevKeys);
  finally
    scan.Free;
    docKeys.Free;
    prevKeys.Free;
    baseKeys.Free;
    notShown.Free;
    defKeys.Free;
  end;
end;

function TTbMainForm.EntryBytes: string;
begin
  Result := TbJoinLines(Editor.Lines, FDoc.LineEnding, FDoc.TrailingEol);
end;

function TTbMainForm.SnippetName: string;
begin
  Result := TbSnippetThemeName(FDoc.FileName, FDoc.BasedOn);
end;

{ ---- the AI ---- }

function TTbMainForm.AiDocument: TTbAiDocument;
begin
  if FSeeds <> nil then
    FSeeds.FlushRadius;      { a spin box step still waiting is part of the text }
  Result := Default(TTbAiDocument);
  Result.Text := Editor.Lines.Text;
  Result.BaseDir := FDoc.BaseDir;
  Result.Untitled := FDoc.Untitled;
  Result.Problems := Copy(FProblems);
end;

function TTbMainForm.BuildCompareForm: TTbCompareForm;
var
  o: TTbAiOutcome;
begin
  o := FAi.Session.Outcome;
  FTrialText := o.Candidate;
  Result := TTbCompareForm.Create(Self);
  Result.OnTrial := @CompareTrial;
  Result.Prepare(o.BaseText, o.Candidate, o.Issues, FLook);
end;

procedure TTbMainForm.AiCandidate(Sender: TObject);
var
  f: TTbCompareForm;
  o: TTbAiOutcome;
begin
  if (FAi = nil) or not FAi.Session.Outcome.HasCandidate then Exit;
  o := FAi.Session.Outcome;
  f := BuildCompareForm;
  try
    if (RunModal(f) = mrOk) and f.Accepted then
      AcceptCandidate(o.BaseText, o.Candidate)
    else
      FAi.Session.MarkLast(False);
  finally
    f.Free;      { the window's close already ended a trial; Free makes sure }
  end;
end;

procedure TTbMainForm.CompareTrial(Sender: TObject; AOn: Boolean; out AError: string);
begin
  AError := '';
  if AOn then
    FPreview.BeginTrial(FTrialText, FDoc.BaseDir, AError)
  else
    FPreview.EndTrial;
  BuildProblems;
end;

function TTbMainForm.AcceptCandidate(const ABase, ACandidate: string): Boolean;
var
  current: string;
begin
  Result := False;
  if FSeeds <> nil then
    FSeeds.FlushRadius;
  current := Editor.Lines.Text;
  { the editor changed after the request went out: say so, and replace what is there now }
  if TbNormalizeEol(current) <> TbNormalizeEol(ABase) then
    if Ask(rsTbAiEditedSince, [mbYes, mbNo], mtConfirmation) <> mrYes then
      Exit;
  Result := ApplyEdits(current, [TbWholeTextEdit(current, TbNormalizeEol(ACandidate))]);
  if Result then
  begin
    FAi.Session.MarkLast(True);
    SetStatus(rsTbAiAccepted);
  end;
end;

function TTbMainForm.BuildAiSettingsForm: TTbAiSettingsForm;
begin
  Result := TTbAiSettingsForm.Create(Self);
  Result.OnAsk := @AskFor;
  Result.Prepare(FAiSettings);
end;

procedure TTbMainForm.AiSettingsClick(Sender: TObject);
var
  f: TTbAiSettingsForm;
begin
  f := BuildAiSettingsForm;
  try
    if RunModal(f) = mrOk then
      FAi.RefreshProfiles;
  finally
    f.Free;
  end;
end;

function TTbMainForm.RunModal(AForm: TCustomForm): TModalResult;
begin
  if Assigned(ShowModalForTest) then
  begin
    ShowModalForTest(AForm);
    Result := AForm.ModalResult;     { freeing the window ends what closing it would }
  end
  else
    Result := AForm.ShowModal;
end;

procedure TTbMainForm.MnuAiSettingsClick(Sender: TObject);
begin
  AiSettingsClick(Sender);
end;

procedure TTbMainForm.MnuAiClick(Sender: TObject);
begin
  ShowSidePage(AiWin);
end;

function TTbMainForm.BuildExportForm: TTbExportForm;
var
  scan: TTbCssScan;
  dual: Boolean;
begin
  FSeeds.FlushRadius;
  scan := TbScanCss(Editor.Lines.Text);
  try
    dual := scan.HasModes;
  finally
    scan.Free;
  end;
  Result := TTbExportForm.Create(nil);
  Result.OnAsk := @AskFor;
  Result.Prepare(EntryBytes, FDoc.BaseDir, SnippetName, dual);
end;

function TTbMainForm.BuildSnippetsForm: TTbSnippetsForm;
var
  fname: string;
begin
  FSeeds.FlushRadius;
  if FDoc.Untitled then
    fname := SnippetName + '.tycss'
  else
    fname := ExtractFileName(FDoc.FileName);
  Result := TTbSnippetsForm.Create(nil);
  Result.Prepare(SnippetName, fname, Editor.Lines.Text);
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
  if Assigned(ToolThemeChangedForTest) then
    ToolThemeChangedForTest(Sender);
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

{ a side page from the View menu: shown (and the bar opened) or, when it is already the one
  showing, the bar folded away }
procedure TTbMainForm.ShowSidePage(AWin: TTyToolWindow);
begin
  if SideBar.Collapsed or (SideBar.ActiveWindow <> AWin) then
  begin
    SideBar.Collapsed := False;
    SideBar.ActivateWindow(AWin);
  end
  else
    SideBar.Collapsed := True;
end;

procedure TTbMainForm.MnuProblemsClick(Sender: TObject);
begin
  ShowSidePage(ProblemsWin);
end;

procedure TTbMainForm.MnuSeedsClick(Sender: TObject);
begin
  ShowSidePage(SeedsWin);
end;

procedure TTbMainForm.MnuCoverageClick(Sender: TObject);
var
  f: TTbCoverageForm;
begin
  f := BuildCoverageForm;
  try
    if (f.ShowModal = mrOk) and (f.Chosen <> '') then
      JumpToTypeKey(f.Chosen);
  finally
    f.Free;
  end;
end;

procedure TTbMainForm.MnuExportClick(Sender: TObject);
var
  f: TTbExportForm;
begin
  f := BuildExportForm;
  try
    if f.ShowModal = mrOk then
      SetStatus(Format(rsTbExported, [f.EdtTarget.Text]));
  finally
    f.Free;
  end;
end;

procedure TTbMainForm.MnuSnippetsClick(Sender: TObject);
var
  f: TTbSnippetsForm;
begin
  f := BuildSnippetsForm;
  try
    f.ShowModal;
  finally
    f.Free;
  end;
end;

end.
