unit umain;

{ File-dialog demo -- all six variants live here:

  Plain    TTyOpenDialog / TTySaveDialog                 (tree + list + look-in + filter + file name)
  Picture  TTyOpenPictureDialog / TTySavePictureDialog   (image preview on the right)
  Preview  TTyOpenPreviewDialog / TTySavePreviewDialog   (image/text preview on the right + custom OnPreview)

  "Open" demonstrates multi-select (Options includes fdoAllowMultiSelect + fdoFileMustExist); the result lists every selected item.
  "Save" demonstrates a default extension + overwrite confirmation (fdoOverwritePrompt).
  "Open Preview" hooks up a custom OnPreview: for formats with no built-in previewer (e.g. .exe/.zip), it hands back a
  block of custom text instead of the "cannot preview" placeholder -- i.e. "the app handles the formats it doesn't recognize".

  All six dialogs are the same custom-drawn TTyFileDialogForm assembled from flags: themed, cross-platform, and needing no image assets. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.TyLabel, tyControls.Button,
  tyControls.Memo, tyControls.Divider, tyControls.ComboBox, tyControls.ToggleSwitch, tyControls.BuiltinThemes,
  tyControls.PreviewBox, tyControls.Dialogs.FileDialog;

type
  TMainForm = class(TTyForm)
    Surface: TTyFormSurface;
    TitleBar1: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    ThemeCombo: TTyComboBox;
    DivFile: TTyDivider;
    BtnOpen:  TTyButton;
    BtnSave:  TTyButton;
    DivPic:   TTyDivider;
    BtnOpenPic: TTyButton;
    BtnSavePic: TTyButton;
    DivPrev:  TTyDivider;
    BtnOpenPrev: TTyButton;
    BtnSavePrev: TTyButton;
    ResultMemo: TTyMemo;

    procedure FormCreate(Sender: TObject);
    procedure BtnOpenClick(Sender: TObject);
    procedure BtnSaveClick(Sender: TObject);
    procedure BtnOpenPicClick(Sender: TObject);
    procedure BtnSavePicClick(Sender: TObject);
    procedure BtnOpenPrevClick(Sender: TObject);
    procedure BtnSavePrevClick(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
  private
    FOpen:     TTyOpenDialog;
    FSave:     TTySaveDialog;
    FOpenPic:  TTyOpenPictureDialog;
    FSavePic:  TTySavePictureDialog;
    FOpenPrev: TTyOpenPreviewDialog;
    FSavePrev: TTySavePreviewDialog;
    procedure Report(const ATitle: string; AOk: Boolean; ADlg: TTyCustomFileDialog);
    procedure PreviewCustom(Sender: TObject; const AFileName: string;
      APreview: TTyPreviewBox; var AHandled: Boolean);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

function ThemesDir: string;
var
  Dir: string;
  i: Integer;
begin
  Dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for i := 1 to 8 do
  begin
    if DirectoryExists(Dir + 'themes') then Exit(Dir + 'themes' + PathDelim);
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if Dir = '' then Break;
  end;
  Result := 'themes' + PathDelim;
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  home: string;
  i: Integer;
begin
  // Built-in themes are compiled in, so the switcher works without locating a themes/ folder.
  TyRegisterBuiltinThemes;
  TyDefaultController.ThemeName := 'default';
  for i := 0 to High(TyBuiltinThemeNames) do
    ThemeCombo.Items.Add(TyBuiltinThemeNames[i]);
  ThemeCombo.ItemIndex := ThemeCombo.Items.IndexOf('default');

  home := ExcludeTrailingPathDelimiter(GetUserDir);

  FOpen := TTyOpenDialog.Create(Self);
  FOpen.Title := 'Open file';
  FOpen.Filter := 'Text (*.txt;*.md)|*.txt;*.md|All files (*.*)|*.*';
  FOpen.InitialDir := home;
  FOpen.Options := [fdoFileMustExist, fdoAllowMultiSelect];

  FSave := TTySaveDialog.Create(Self);
  FSave.Title := 'Save file';
  FSave.Filter := 'Text (*.txt)|*.txt|All files (*.*)|*.*';
  FSave.DefaultExt := 'txt';
  FSave.InitialDir := home;
  FSave.Options := [fdoOverwritePrompt];

  FOpenPic := TTyOpenPictureDialog.Create(Self);
  FOpenPic.Title := 'Open picture';
  FOpenPic.InitialDir := home;

  FSavePic := TTySavePictureDialog.Create(Self);
  FSavePic.Title := 'Save picture';
  FSavePic.DefaultExt := 'png';
  FSavePic.InitialDir := home;

  FOpenPrev := TTyOpenPreviewDialog.Create(Self);
  FOpenPrev.Title := 'Open (with preview)';
  FOpenPrev.InitialDir := home;
  FOpenPrev.OnPreview := @PreviewCustom;   { custom: handle formats with no built-in previewer }

  FSavePrev := TTySavePreviewDialog.Create(Self);
  FSavePrev.Title := 'Save (with preview)';
  FSavePrev.InitialDir := home;

  ApplyChromeTheme(TyDefaultController);
end;

{ Custom preview: the built-in path recognizes images and common text; here we demonstrate taking over the
  "unrecognized" formats (pkOther, e.g. .exe/.zip) -- handing back a block of custom text instead of letting it
  fall through to the "cannot preview" placeholder. Set AHandled to skip the built-in dispatch. }
procedure TMainForm.PreviewCustom(Sender: TObject; const AFileName: string;
  APreview: TTyPreviewBox; var AHandled: Boolean);
begin
  if (AFileName = '') or DirectoryExists(AFileName) then Exit;
  if TyPreviewClassify(AFileName) = pkOther then
  begin
    APreview.ShowText(
      'Custom preview (OnPreview)' + LineEnding + LineEnding +
      'File:' + ExtractFileName(AFileName) + LineEnding +
      'Extension:' + ExtractFileExt(AFileName) + LineEnding + LineEnding +
      'This format has no built-in previewer; it is handled by the app''s OnPreview.' + LineEnding +
      'In a real scenario you could decode it into a bitmap (ShowImage) or text (ShowText).');
    AHandled := True;
  end;
  { other formats stay un-handled -> built-in: image -> text -> "cannot preview" }
end;

procedure TMainForm.Report(const ATitle: string; AOk: Boolean; ADlg: TTyCustomFileDialog);
var
  i: Integer;
begin
  if not AOk then
  begin
    ResultMemo.Lines.Add(ATitle + ':(cancel)');
    Exit;
  end;
  if ADlg.Files.Count > 1 then
  begin
    ResultMemo.Lines.Add(Format('%s: %d item(s) selected', [ATitle, ADlg.Files.Count]));
    for i := 0 to ADlg.Files.Count - 1 do
      ResultMemo.Lines.Add('    ' + ADlg.Files[i]);
  end
  else
    ResultMemo.Lines.Add(ATitle + ':' + ADlg.FileName);
end;

procedure TMainForm.BtnOpenClick(Sender: TObject);
begin
  Report('Open', FOpen.Execute, FOpen);
end;

procedure TMainForm.BtnSaveClick(Sender: TObject);
begin
  Report('Save', FSave.Execute, FSave);
end;

procedure TMainForm.BtnOpenPicClick(Sender: TObject);
begin
  Report('Open picture', FOpenPic.Execute, FOpenPic);
end;

procedure TMainForm.BtnSavePicClick(Sender: TObject);
begin
  Report('Save picture', FSavePic.Execute, FSavePic);
end;

procedure TMainForm.BtnOpenPrevClick(Sender: TObject);
begin
  Report('Open preview', FOpenPrev.Execute, FOpenPrev);
end;

procedure TMainForm.BtnSavePrevClick(Sender: TObject);
begin
  Report('Save preview', FSavePrev.Execute, FSavePrev);
end;

procedure TMainForm.ThemeComboChange(Sender: TObject);
begin
  if ThemeCombo.ItemIndex < 0 then Exit;
  TyDefaultController.ThemeName := ThemeCombo.Items[ThemeCombo.ItemIndex];
  ApplyChromeTheme(TyDefaultController);   // re-theme the shell on every skin change
end;

procedure TMainForm.DarkSwitchChange(Sender: TObject);
begin
  // Flip the light/dark @mode axis (independent of which theme ThemeCombo picked).
  if DarkSwitch.Checked then
    TyDefaultController.Mode := 'dark'
  else
    TyDefaultController.Mode := 'light';
  ApplyChromeTheme(TyDefaultController);
end;

end.
