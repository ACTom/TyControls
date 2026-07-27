unit umain;

{ File-dialog demo -- all six variants live here:

  Plain    TTyOpenDialog / TTySaveDialog                 (tree + list + look-in + filter + file name)
  Picture  TTyOpenPictureDialog / TTySavePictureDialog   (image preview on the right)
  Preview  TTyOpenPreviewDialog / TTySavePreviewDialog   (image/text preview on the right + custom OnPreview)

  All six are NON-VISUAL COMPONENTS dropped in umain.lfm: Title / Filter / FilterIndex / FileName /
  DefaultExt / Options and the OnShow / OnClose / OnCanClose / OnPreview events are Object-Inspector
  settings, exactly as you would wire them in your own form. The code below only fills in InitialDir
  (a runtime path) and handles the events.

  "Open" demonstrates multi-select (Options = fdoFileMustExist + fdoPathMustExist + fdoAllowMultiSelect),
  starts on the second filter (FilterIndex = 2) and logs its OnShow / OnClose.
  "Save" demonstrates a default extension, overwrite confirmation (fdoOverwritePrompt), a pre-filled
  FileName -- and OnCanClose, which can refuse the OK and keep the dialog open (tick the check box).
  "Open Preview" hooks up a custom OnPreview covering three of the preview box's render entry points:
  ShowMessage (a 0-byte file), ShowCustom + OnPaintPreview (owner-drawn, for .exe/.zip and friends)
  and ShowText (any other format with no built-in previewer).

  The last section calls the unit's LCL-parity global one-liners -- no component, just a var and a call.

  All six dialogs are the same custom-drawn TTyFileDialogForm assembled from flags: themed, cross-platform, and needing no image assets. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Graphics, Forms, Controls,
  tyControls.Types, tyControls.Painter,
  tyControls.Controller, tyControls.Form, tyControls.TyLabel, tyControls.Button,
  tyControls.Memo, tyControls.Divider, tyControls.ComboBox, tyControls.ToggleSwitch, tyControls.BuiltinThemes,
  tyControls.CheckBox, tyControls.PaintPanel,
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
    ChkVetoSave: TTyCheckBox;
    LblOpenNote: TTyLabel;
    LblSaveNote: TTyLabel;
    DivPic:   TTyDivider;
    BtnOpenPic: TTyButton;
    BtnSavePic: TTyButton;
    DivPrev:  TTyDivider;
    BtnOpenPrev: TTyButton;
    BtnSavePrev: TTyButton;
    LblPrevNote: TTyLabel;
    DivGlobal: TTyDivider;
    BtnGlobOpen: TTyButton;
    BtnGlobSave: TTyButton;
    BtnGlobOpenPic: TTyButton;
    BtnGlobSavePic: TTyButton;
    BtnGlobOpenPrev: TTyButton;
    BtnGlobSavePrev: TTyButton;
    ResultMemo: TTyMemo;
    { The six dialog components -- designed in umain.lfm, not built in code. }
    DlgOpen:     TTyOpenDialog;
    DlgSave:     TTySaveDialog;
    DlgOpenPic:  TTyOpenPictureDialog;
    DlgSavePic:  TTySavePictureDialog;
    DlgOpenPrev: TTyOpenPreviewDialog;
    DlgSavePrev: TTySavePreviewDialog;

    procedure FormCreate(Sender: TObject);
    procedure BtnOpenClick(Sender: TObject);
    procedure BtnSaveClick(Sender: TObject);
    procedure BtnOpenPicClick(Sender: TObject);
    procedure BtnSavePicClick(Sender: TObject);
    procedure BtnOpenPrevClick(Sender: TObject);
    procedure BtnSavePrevClick(Sender: TObject);
    procedure BtnGlobOpenClick(Sender: TObject);
    procedure BtnGlobSaveClick(Sender: TObject);
    procedure BtnGlobOpenPicClick(Sender: TObject);
    procedure BtnGlobSavePicClick(Sender: TObject);
    procedure BtnGlobOpenPrevClick(Sender: TObject);
    procedure BtnGlobSavePrevClick(Sender: TObject);
    { Dialog lifecycle -- TyForwardDialogEvents relays these onto the transient dialog FORM,
      so Sender is that form, not the component. }
    procedure DlgOpenShow(Sender: TObject);
    procedure DlgOpenClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure DlgSaveCanClose(Sender: TObject; var CanClose: Boolean);
    procedure PreviewCustom(Sender: TObject; const AFileName: string;
      APreview: TTyPreviewBox; var AHandled: Boolean);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
  private
    FPreviewExt: string;   { what PreviewPaint stamps on the owner-drawn card }
    procedure Report(const ATitle: string; AOk: Boolean; ADlg: TTyCustomFileDialog);
    procedure PreviewPaint(Sender: TObject; APainter: TTyPainter; const AContent: TRect);
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

{ Size of an existing file in bytes; -1 when it cannot be stat'ed. }
function FileSizeOf(const AFileName: string): Int64;
var
  sr: TSearchRec;
begin
  Result := -1;
  if FindFirst(AFileName, faAnyFile, sr) = 0 then
  begin
    Result := sr.Size;
    FindClose(sr);
  end;
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

  { Everything else about the six dialogs is designed in the .lfm; only the start directory
    is a runtime value, so only it is set here. }
  home := ExcludeTrailingPathDelimiter(GetUserDir);
  DlgOpen.InitialDir     := home;
  DlgSave.InitialDir     := home;
  DlgOpenPic.InitialDir  := home;
  DlgSavePic.InitialDir  := home;
  DlgOpenPrev.InitialDir := home;
  DlgSavePrev.InitialDir := home;

  ApplyChromeTheme(TyDefaultController);
end;

{ Custom preview: the built-in path recognizes images and common text; here we demonstrate taking over the
  "unrecognized" formats (pkOther, e.g. .exe/.zip) -- and the preview box's three non-file render entry
  points. Set AHandled to skip the built-in dispatch. }
procedure TMainForm.PreviewCustom(Sender: TObject; const AFileName: string;
  APreview: TTyPreviewBox; var AHandled: Boolean);
var
  ext: string;
begin
  if (AFileName = '') or DirectoryExists(AFileName) then Exit;

  { ShowMessage -- a centred placeholder. A 0-byte file has nothing to show whatever its
    extension claims, so take it over before the built-in image/text dispatch runs. }
  if FileSizeOf(AFileName) = 0 then
  begin
    APreview.ShowMessage('Empty file (0 bytes) — nothing to preview');
    AHandled := True;
    Exit;
  end;

  { Images and known text formats keep the built-in preview. }
  if TyPreviewClassify(AFileName) <> pkOther then Exit;

  ext := LowerCase(ExtractFileExt(AFileName));
  if (ext = '.exe') or (ext = '.dll') or (ext = '.zip') or (ext = '.7z') or (ext = '.rar') then
  begin
    { ShowCustom -- owner-draw. The box switches to custom mode and hands its live TTyPainter
      to OnPaintPreview on every repaint, so the app renders the pane itself. }
    FPreviewExt := UpperCase(Copy(ext, 2, Length(ext)));
    APreview.OnPaintPreview := @PreviewPaint;
    APreview.ShowCustom;
    AHandled := True;
    Exit;
  end;

  { ShowText -- hand back a block of text instead of the "cannot preview" placeholder. }
  APreview.ShowText(
    'Custom preview (OnPreview)' + LineEnding + LineEnding +
    'File:' + ExtractFileName(AFileName) + LineEnding +
    'Extension:' + ExtractFileExt(AFileName) + LineEnding + LineEnding +
    'This format has no built-in previewer; it is handled by the app''s OnPreview.' + LineEnding +
    'In a real scenario you could decode it into a bitmap (ShowImage) or text (ShowText).');
  AHandled := True;
end;

{ The ShowCustom pane. Draw with the painter the box hands over -- never with the raw canvas:
  the painter composites into its own bitmap and blits it at EndPaint. }
procedure TMainForm.PreviewPaint(Sender: TObject; APainter: TTyPainter; const AContent: TRect);
var
  card: TRect;
  pad: Integer;
begin
  pad := APainter.Scale(8);
  card := Rect(AContent.Left + pad, AContent.Top + pad,
               AContent.Right - pad, AContent.Top + pad + APainter.Scale(90));
  APainter.StrokeBorder(card, 6, 1, TyRGBA($3B, $82, $F6, 220));
  APainter.DrawText(card, FPreviewExt, '', 22, 700,
    TyRGBA($3B, $82, $F6, 255), taCenter, tlCenter, False);
  APainter.DrawText(
    Rect(AContent.Left, card.Bottom + pad, AContent.Right, card.Bottom + pad + APainter.Scale(20)),
    'ShowCustom + OnPaintPreview', '', 10, 400,
    TyRGBA($6B, $72, $80, 255), taCenter, tlTop, False);
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
  Report('Open', DlgOpen.Execute, DlgOpen);
end;

procedure TMainForm.BtnSaveClick(Sender: TObject);
begin
  Report('Save', DlgSave.Execute, DlgSave);
end;

procedure TMainForm.BtnOpenPicClick(Sender: TObject);
begin
  Report('Open picture', DlgOpenPic.Execute, DlgOpenPic);
end;

procedure TMainForm.BtnSavePicClick(Sender: TObject);
begin
  Report('Save picture', DlgSavePic.Execute, DlgSavePic);
end;

procedure TMainForm.BtnOpenPrevClick(Sender: TObject);
begin
  Report('Open preview', DlgOpenPrev.Execute, DlgOpenPrev);
end;

procedure TMainForm.BtnSavePrevClick(Sender: TObject);
begin
  Report('Save preview', DlgSavePrev.Execute, DlgSavePrev);
end;

{ ---------------------------------------------------------------------------
  Dialog lifecycle: OnShow / OnClose bracket every Execute, OnCanClose can veto it.
  --------------------------------------------------------------------------- }

procedure TMainForm.DlgOpenShow(Sender: TObject);
begin
  ResultMemo.Lines.Add('--- OnShow: the Open dialog is up ---');
end;

procedure TMainForm.DlgOpenClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  ResultMemo.Lines.Add('--- OnClose: the Open dialog is gone ---');
end;

procedure TMainForm.DlgSaveCanClose(Sender: TObject; var CanClose: Boolean);
begin
  { The veto seam. Only ever refuse an OK -- vetoing a Cancel would trap the user in the dialog. }
  if not (Sender is TCustomForm) then Exit;
  if TCustomForm(Sender).ModalResult <> mrOK then Exit;
  if ChkVetoSave.Checked then
  begin
    CanClose := False;
    ResultMemo.Lines.Add('Save: OnCanClose returned False — the dialog stays open');
  end;
end;

{ ---------------------------------------------------------------------------
  The unit-level one-liners: no component, no owner, no properties -- a var and a call.
  --------------------------------------------------------------------------- }

procedure TMainForm.BtnGlobOpenClick(Sender: TObject);
var
  fn: string;
begin
  fn := '';
  if TyOpenDialog(fn, 'All files (*.*)|*.*') then
    ResultMemo.Lines.Add('TyOpenDialog(): ' + fn)
  else
    ResultMemo.Lines.Add('TyOpenDialog(): (cancel)');
end;

procedure TMainForm.BtnGlobSaveClick(Sender: TObject);
var
  fn: string;
begin
  fn := '';
  if TySaveDialog(fn, 'Text (*.txt)|*.txt|All files (*.*)|*.*', 'txt') then
    ResultMemo.Lines.Add('TySaveDialog(): ' + fn)
  else
    ResultMemo.Lines.Add('TySaveDialog(): (cancel)');
end;

procedure TMainForm.BtnGlobOpenPicClick(Sender: TObject);
var
  fn: string;
begin
  fn := '';
  if TyOpenPictureDialog(fn) then
    ResultMemo.Lines.Add('TyOpenPictureDialog(): ' + fn)
  else
    ResultMemo.Lines.Add('TyOpenPictureDialog(): (cancel)');
end;

procedure TMainForm.BtnGlobSavePicClick(Sender: TObject);
var
  fn: string;
begin
  fn := '';
  if TySavePictureDialog(fn) then
    ResultMemo.Lines.Add('TySavePictureDialog(): ' + fn)
  else
    ResultMemo.Lines.Add('TySavePictureDialog(): (cancel)');
end;

procedure TMainForm.BtnGlobOpenPrevClick(Sender: TObject);
var
  fn: string;
begin
  fn := '';
  if TyOpenPreviewDialog(fn) then
    ResultMemo.Lines.Add('TyOpenPreviewDialog(): ' + fn)
  else
    ResultMemo.Lines.Add('TyOpenPreviewDialog(): (cancel)');
end;

procedure TMainForm.BtnGlobSavePrevClick(Sender: TObject);
var
  fn, ext: string;
begin
  fn := '';
  ext := 'txt';   { both parameters are var -- the call may rewrite them }
  if TySavePreviewDialog(fn, ext) then
    ResultMemo.Lines.Add('TySavePreviewDialog(): ' + fn)
  else
    ResultMemo.Lines.Add('TySavePreviewDialog(): (cancel)');
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
