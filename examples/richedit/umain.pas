unit umain;

{ TTyRichEdit as a small word processor (a self-drawn TTyForm with its title bar and menu bar):
  - the menus and the toolbar are made of tyControls.RichEdit.Actions: the character styles,
    alignment, lists, indent, a picture, a table, find and replace, undo and redo, zoom - each
    action's Enabled and Checked are the rich edit's own answers, its run one undo step;
  - a TTyRichEditRuler above the text shows the caret paragraph's indents and tab stops, and
    dragging them formats the paragraphs;
  - the status bar shows what the rich edit refused (OnEditRefused: never a dialog), what was
    not found, the line and column of the caret, the zoom, and a large file's load;
  - File opens and saves RTF and plain text through the package's file dialogs; Samples opens
    a few documents kept in samples/ (Chinese text and its formats, a table, pictures, Word's
    table of contents with its links) - read from a stream, so Save asks for a new name;
  - View > Skin follows the skins the package has, View > Dark their dark mode.
  The window, the menus, the toolbar and the actions are in umain.lfm; the code here is the
  application's part: files, the status bar, the skin menu. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, Menus, ActnList,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes, tyControls.Menu,
  tyControls.ToolBar, tyControls.GlyphButtons, tyControls.IconFont, tyControls.Icons.Lucide,
  tyControls.StatusBar, tyControls.Dialogs, tyControls.Dialogs.FileDialog,
  tyControls.RichEdit.Layout, tyControls.RichEdit, tyControls.RichEdit.Ruler,
  tyControls.RichEdit.Actions;

type
  TMainForm = class(TTyForm)
    Surface: TTyFormSurface;
    Bar: TTyTitleBar;
    MainMenuBar: TTyMenuBar;
    Tools: TTyToolBar;
    BtnNew: TTySpeedButton;
    BtnOpen: TTySpeedButton;
    BtnSave: TTySpeedButton;
    Sep1: TTyToolSeparator;
    BtnUndo: TTySpeedButton;
    BtnRedo: TTySpeedButton;
    Sep2: TTyToolSeparator;
    BtnBold: TTySpeedButton;
    BtnItalic: TTySpeedButton;
    BtnUnderline: TTySpeedButton;
    BtnStrikeOut: TTySpeedButton;
    BtnSuperscript: TTySpeedButton;
    BtnSubscript: TTySpeedButton;
    Sep3: TTyToolSeparator;
    BtnAlignLeft: TTySpeedButton;
    BtnAlignCenter: TTySpeedButton;
    BtnAlignRight: TTySpeedButton;
    BtnJustify: TTySpeedButton;
    Sep4: TTyToolSeparator;
    BtnBullets: TTySpeedButton;
    BtnNumbering: TTySpeedButton;
    BtnIndentDecrease: TTySpeedButton;
    BtnIndentIncrease: TTySpeedButton;
    Sep5: TTyToolSeparator;
    BtnInsertPicture: TTySpeedButton;
    BtnInsertTable: TTySpeedButton;
    Sep6: TTyToolSeparator;
    BtnFind: TTySpeedButton;
    BtnReplace: TTySpeedButton;
    Sep7: TTyToolSeparator;
    BtnZoomOut: TTySpeedButton;
    BtnZoomIn: TTySpeedButton;
    Ruler: TTyRichEditRuler;
    Status: TTyStatusBar;
    Editor: TTyRichEdit;
    LucideFont: TTyLucideIconFont;
    DlgOpen: TTyOpenDialog;
    DlgSave: TTySaveDialog;
    Actions: TActionList;
    ActNew: TAction;
    ActOpen: TAction;
    ActSave: TAction;
    ActSaveAs: TAction;
    ActExit: TAction;
    ActBold: TTyRichEditBold;
    ActItalic: TTyRichEditItalic;
    ActUnderline: TTyRichEditUnderline;
    ActStrikeOut: TTyRichEditStrikeOut;
    ActSuperscript: TTyRichEditSuperscript;
    ActSubscript: TTyRichEditSubscript;
    ActAlignLeft: TTyRichEditAlignLeft;
    ActAlignCenter: TTyRichEditAlignCenter;
    ActAlignRight: TTyRichEditAlignRight;
    ActJustify: TTyRichEditAlignJustify;
    ActBullets: TTyRichEditBullets;
    ActNumbering: TTyRichEditNumbering;
    ActIndentIncrease: TTyRichEditIndentIncrease;
    ActIndentDecrease: TTyRichEditIndentDecrease;
    ActInsertPicture: TTyRichEditInsertPicture;
    ActInsertTable: TTyRichEditInsertTable;
    ActFind: TTyRichEditFind;
    ActReplace: TTyRichEditReplace;
    ActUndo: TTyRichEditUndo;
    ActRedo: TTyRichEditRedo;
    ActZoomIn: TTyRichEditZoomIn;
    ActZoomOut: TTyRichEditZoomOut;
    ActZoomReset: TTyRichEditZoomReset;
    MainMenu1: TMainMenu;
    MnuFile: TMenuItem;
    MnuNew: TMenuItem;
    MnuOpen: TMenuItem;
    MnuSave: TMenuItem;
    MnuSaveAs: TMenuItem;
    MnuSep1: TMenuItem;
    MnuSamples: TMenuItem;
    MnuSampleFormats: TMenuItem;
    MnuSampleTable: TMenuItem;
    MnuSamplePictures: TMenuItem;
    MnuSampleToc: TMenuItem;
    MnuSep2: TMenuItem;
    MnuExit: TMenuItem;
    MnuEdit: TMenuItem;
    MnuUndo: TMenuItem;
    MnuRedo: TMenuItem;
    MnuSep3: TMenuItem;
    MnuFind: TMenuItem;
    MnuReplace: TMenuItem;
    MnuFormat: TMenuItem;
    MnuBold: TMenuItem;
    MnuItalic: TMenuItem;
    MnuUnderline: TMenuItem;
    MnuStrikeOut: TMenuItem;
    MnuSuperscript: TMenuItem;
    MnuSubscript: TMenuItem;
    MnuSep4: TMenuItem;
    MnuAlignLeft: TMenuItem;
    MnuAlignCenter: TMenuItem;
    MnuAlignRight: TMenuItem;
    MnuJustify: TMenuItem;
    MnuSep5: TMenuItem;
    MnuBullets: TMenuItem;
    MnuNumbering: TMenuItem;
    MnuIndentIncrease: TMenuItem;
    MnuIndentDecrease: TMenuItem;
    MnuInsert: TMenuItem;
    MnuInsertPicture: TMenuItem;
    MnuInsertTable: TMenuItem;
    MnuView: TMenuItem;
    MnuZoomIn: TMenuItem;
    MnuZoomOut: TMenuItem;
    MnuZoomReset: TMenuItem;
    MnuSep6: TMenuItem;
    MnuWrap: TMenuItem;
    MnuWrapWindow: TMenuItem;
    MnuWrapPage: TMenuItem;
    MnuWrapNone: TMenuItem;
    MnuReadOnly: TMenuItem;
    MnuSep7: TMenuItem;
    MnuSkin: TMenuItem;
    MnuDark: TMenuItem;
    procedure FormCreate(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure ActNewExecute(Sender: TObject);
    procedure ActOpenExecute(Sender: TObject);
    procedure ActSaveExecute(Sender: TObject);
    procedure ActSaveAsExecute(Sender: TObject);
    procedure ActExitExecute(Sender: TObject);
    procedure SampleClick(Sender: TObject);
    procedure WrapClick(Sender: TObject);
    procedure ReadOnlyClick(Sender: TObject);
    procedure DarkClick(Sender: TObject);
    procedure SkinClick(Sender: TObject);
    procedure EditorEditRefused(Sender: TObject; const AReason: string);
    procedure EditorLoadProgress(Sender: TObject; ADone, ATotal: Int64; var ACancel: Boolean);
    procedure EditorModifiedChange(Sender: TObject);
    procedure EditorSelectionChange(Sender: TObject);
    procedure EditorZoomChange(Sender: TObject);
    procedure FindNotFound(Sender: TObject; const AText: string);
    procedure ReplaceReplaced(Sender: TObject; ACount: Integer);
    procedure TableChooseSize(Sender: TObject; var ARows, AColumns: Integer;
      var AInsert: Boolean);
  private
    procedure Tell(const AText: string);
    procedure ShowCaret;
    procedure ShowZoom;
    procedure ShowTitle;
    procedure SetSkin(const AName: string);
    { Asks to save a changed document first; False: the user cancelled. }
    function MaySetAside: Boolean;
    function SaveAs: Boolean;
    function SamplesDir: string;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

resourcestring
  rsLineColumn   = 'Line %d, column %d';
  rsZoomPercent  = '%d %%';
  rsNotFound     = 'Cannot find "%s".';
  rsReplaced     = '%d replaced.';
  rsLoading      = 'Loading: %d %%';
  rsLoaded       = 'Loaded.';
  rsSaved        = 'Saved: %s';
  rsUntitled     = 'Untitled';
  rsSaveChanges  = 'The document has changed. Save it first?';
  rsOpenFailed   = 'The file cannot be opened: %s';
  rsSaveFailed   = 'The file cannot be saved: %s';
  rsTableTitle   = 'Insert table';
  rsTablePrompt  = 'Rows x columns:';
  rsTableBadSize = 'Give the size as rows x columns, for example 3 x 4.';
  rsOpenFilter   = 'Documents (*.rtf;*.txt)|*.rtf;*.txt|Rich text (*.rtf)|*.rtf|Text (*.txt)|*.txt|All files|*';
  rsSaveFilter   = 'Rich text (*.rtf)|*.rtf|Text (*.txt)|*.txt';

procedure TMainForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  i: Integer;
  item: TMenuItem;
begin
  // the skins are compiled in: the menu lists them without a themes/ folder
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do
  begin
    item := TMenuItem.Create(Self);
    item.Caption := names[i];
    item.RadioItem := True;
    item.GroupIndex := 1;
    item.OnClick := @SkinClick;
    MnuSkin.Add(item);
  end;
  DlgOpen.Filter := rsOpenFilter;
  DlgSave.Filter := rsSaveFilter;
  SetSkin('default');
  MnuWrapWindow.Checked := True;
  ShowCaret;
  ShowZoom;
  ShowTitle;
end;

procedure TMainForm.SetSkin(const AName: string);
var
  i: Integer;
begin
  TyDefaultController.ThemeName := AName;
  ApplyChromeTheme(TyDefaultController);
  for i := 0 to MnuSkin.Count - 1 do
    MnuSkin.Items[i].Checked := SameText(MnuSkin.Items[i].Caption, AName);
end;

procedure TMainForm.SkinClick(Sender: TObject);
begin
  SetSkin(TMenuItem(Sender).Caption);
end;

procedure TMainForm.DarkClick(Sender: TObject);
begin
  MnuDark.Checked := not MnuDark.Checked;
  if MnuDark.Checked then TyDefaultController.Mode := 'dark'
  else TyDefaultController.Mode := 'light';
  ApplyChromeTheme(TyDefaultController);
end;

procedure TMainForm.Tell(const AText: string);
begin
  Status.Panels[0].Text := AText;
end;

procedure TMainForm.ShowCaret;
var
  p: TPoint;
begin
  p := Editor.CaretPos;
  Status.Panels[1].Text := Format(rsLineColumn, [p.Y + 1, p.X + 1]);
end;

procedure TMainForm.ShowZoom;
begin
  Status.Panels[2].Text := Format(rsZoomPercent, [Editor.Zoom]);
end;

procedure TMainForm.ShowTitle;
var
  s: string;
begin
  if Editor.SourceFile <> '' then s := ExtractFileName(Editor.SourceFile) else s := rsUntitled;
  if Editor.Modified then s := '* ' + s;
  Bar.Caption := s + '  · TyControls';
end;

procedure TMainForm.EditorEditRefused(Sender: TObject; const AReason: string);
begin
  // a refusal is the status bar's, never a dialog: the user goes on typing
  Tell(AReason);
end;

procedure TMainForm.EditorLoadProgress(Sender: TObject; ADone, ATotal: Int64;
  var ACancel: Boolean);
begin
  if (ATotal > 0) and (ADone < ATotal) then Tell(Format(rsLoading, [ADone * 100 div ATotal]))
  else Tell(rsLoaded);
end;

procedure TMainForm.EditorModifiedChange(Sender: TObject);
begin
  ShowTitle;
end;

procedure TMainForm.EditorSelectionChange(Sender: TObject);
begin
  ShowCaret;
end;

procedure TMainForm.EditorZoomChange(Sender: TObject);
begin
  ShowZoom;
end;

procedure TMainForm.FindNotFound(Sender: TObject; const AText: string);
begin
  Tell(Format(rsNotFound, [AText]));
end;

procedure TMainForm.ReplaceReplaced(Sender: TObject; ACount: Integer);
begin
  Tell(Format(rsReplaced, [ACount]));
end;

procedure TMainForm.TableChooseSize(Sender: TObject; var ARows, AColumns: Integer;
  var AInsert: Boolean);
var
  s: string;
  p, r, c: Integer;
begin
  s := Format('%d x %d', [ARows, AColumns]);
  AInsert := TyInputQuery(rsTableTitle, rsTablePrompt, s);
  if not AInsert then Exit;
  s := LowerCase(StringReplace(s, ' ', '', [rfReplaceAll]));
  p := Pos('x', s);
  if (p > 0) and TryStrToInt(Copy(s, 1, p - 1), r) and TryStrToInt(Copy(s, p + 1, MaxInt), c) then
  begin
    ARows := r;
    AColumns := c;
  end
  else
  begin
    AInsert := False;
    Tell(rsTableBadSize);
  end;
end;

function TMainForm.MaySetAside: Boolean;
begin
  Result := True;
  if not Editor.Modified then Exit;
  case TyMessageDlg(rsSaveChanges, mtConfirmation, [mbYes, mbNo, mbCancel]) of
    mrYes:
      begin
        ActSaveExecute(nil);
        Result := not Editor.Modified;
      end;
    mrNo: Result := True;
  else
    Result := False;
  end;
end;

procedure TMainForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := MaySetAside;
end;

procedure TMainForm.ActNewExecute(Sender: TObject);
begin
  if not MaySetAside then Exit;
  Editor.Clear;
  Editor.PlainText := False;
  Tell('');
  ShowTitle;
end;

procedure TMainForm.ActOpenExecute(Sender: TObject);
begin
  if not MaySetAside then Exit;
  if not DlgOpen.Execute then Exit;
  try
    // the format from the file itself (an RTF file is read as RTF whatever its name)
    Editor.LoadFromFile(DlgOpen.FileName);
    Tell('');
  except
    on E: Exception do Tell(Format(rsOpenFailed, [E.Message]));
  end;
  ShowTitle;
end;

procedure TMainForm.ActSaveExecute(Sender: TObject);
begin
  if Editor.SourceFile = '' then
  begin
    SaveAs;
    Exit;
  end;
  try
    // in the format it was opened in (a text file stays text, an RTF file RTF)
    Editor.SaveToFile(Editor.SourceFile, Editor.SourceFormat);
    Tell(Format(rsSaved, [Editor.SourceFile]));
  except
    on E: Exception do Tell(Format(rsSaveFailed, [E.Message]));
  end;
  ShowTitle;
end;

procedure TMainForm.ActSaveAsExecute(Sender: TObject);
begin
  SaveAs;
end;

function TMainForm.SaveAs: Boolean;
var
  fmt: TTyRichFormat;
begin
  Result := False;
  if Editor.PlainText then DlgSave.FilterIndex := 2 else DlgSave.FilterIndex := 1;
  if not DlgSave.Execute then Exit;
  if DlgSave.FilterIndex = 2 then fmt := rfText else fmt := rfRtf;
  try
    Editor.SaveToFile(DlgSave.FileName, fmt);
    Tell(Format(rsSaved, [DlgSave.FileName]));
    Result := True;
  except
    on E: Exception do Tell(Format(rsSaveFailed, [E.Message]));
  end;
  ShowTitle;
end;

procedure TMainForm.ActExitExecute(Sender: TObject);
begin
  Close;
end;

function TMainForm.SamplesDir: string;
var
  dir: string;
  i: Integer;
begin
  // beside the program, or up from it (the build may put it in a folder of its own)
  dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for i := 1 to 8 do
  begin
    if DirectoryExists(dir + 'samples') then Exit(dir + 'samples' + PathDelim);
    dir := ExtractFilePath(ExcludeTrailingPathDelimiter(dir));
    if dir = '' then Break;
  end;
  Result := 'samples' + PathDelim;
end;

procedure TMainForm.SampleClick(Sender: TObject);
var
  sample: string;
  f: TFileStream;
begin
  if Sender = MnuSampleFormats then sample := 'wp-styles.rtf'
  else if Sender = MnuSampleTable then sample := 'wp-zh-table.rtf'
  else if Sender = MnuSamplePictures then sample := 're-zh-picture.rtf'
  else sample := 'word-toc.rtf';
  if not MaySetAside then Exit;
  try
    // read from a stream: the sample is not the document's file, so Save asks for a sample
    f := TFileStream.Create(SamplesDir + sample, fmOpenRead or fmShareDenyWrite);
    try
      Editor.LoadFromStream(f, rfRtf);
    finally
      f.Free;
    end;
    Tell(sample);
  except
    on E: Exception do Tell(Format(rsOpenFailed, [E.Message]));
  end;
  ShowTitle;
end;

procedure TMainForm.WrapClick(Sender: TObject);
begin
  TMenuItem(Sender).Checked := True;
  if Sender = MnuWrapPage then Editor.WrapMode := rwmPage
  else if Sender = MnuWrapNone then Editor.WrapMode := rwmNone
  else Editor.WrapMode := rwmWindow;
end;

procedure TMainForm.ReadOnlyClick(Sender: TObject);
begin
  MnuReadOnly.Checked := not MnuReadOnly.Checked;
  Editor.ReadOnly := MnuReadOnly.Checked;
end;

end.
