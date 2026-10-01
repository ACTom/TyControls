unit tbexportform;
{ "File > Export theme bundle...": name, author and version for theme.json, a folder or a
  zip, where to. The files that go in are listed before anything is written; a reference
  that cannot go in (tbexport) disables Export and says why, and a theme that refers to
  other files cannot be a zip (the library's zip reader would not find them) -- that choice
  is greyed with the reason. Replacing an existing zip is asked once (OnAsk); a folder must
  not exist yet or be empty. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Forms, Controls, Dialogs,
  tyControls.Controller, tyControls.Form, tyControls.FormSurface, tyControls.TyLabel,
  tyControls.Edit, tyControls.CheckBox, tyControls.ListBox, tyControls.Button,
  tyControls.Dialogs.SelectPath, tyControls.Dialogs.FileDialog,
  tbexport, tbseedsframe;

resourcestring
  rsTbExportOnlyTheme = '(none)';
  rsTbExportOverwrite = '%s exists. Replace it?';

type
  TTbExportForm = class(TTyForm)
    Surface: TTyFormSurface;
    Bar: TTyTitleBar;
    LblName: TTyLabel;
    EdtName: TTyEdit;
    LblAuthor: TTyLabel;
    EdtAuthor: TTyEdit;
    LblVersion: TTyLabel;
    EdtVersion: TTyEdit;
    RadFolder: TTyRadioButton;
    RadZip: TTyRadioButton;
    LblTarget: TTyLabel;
    EdtTarget: TTyEdit;
    BtnBrowse: TTyButton;
    LblFiles: TTyLabel;
    LstFiles: TTyListBox;
    LblNote: TTyLabel;
    BtnExport: TTyButton;
    BtnCancel: TTyButton;
    DlgFolder: TTySelectPathDialog;
    DlgZip: TTySaveDialog;
    procedure FormCreate(Sender: TObject);
    procedure FormatChange(Sender: TObject);
    procedure BtnBrowseClick(Sender: TObject);
    procedure BtnExportClick(Sender: TObject);
  private
    FEntry: string;
    FBaseDir: string;
    FDualMode: Boolean;
    FFiles: TTbBundleFiles;
    FCollectError: string;
    FUpdating: Boolean;
    FOnAsk: TTbAskEvent;
    function ChosenFormat: TTbBundleFormat;
  public
    procedure Prepare(const AEntry, ABaseDir, AName: string; ADualMode: Boolean);
    function DoExport(out AError: string): Boolean;
    property Files: TTbBundleFiles read FFiles;
    property CollectError: string read FCollectError;
    property OnAsk: TTbAskEvent read FOnAsk write FOnAsk;   { "replace the zip?" }
  end;

implementation

{$R *.lfm}

const
  cZipExt = '.zip';

procedure TTbExportForm.FormCreate(Sender: TObject);
begin
  ApplyChromeTheme(TyDefaultController);
end;

function TTbExportForm.ChosenFormat: TTbBundleFormat;
begin
  if RadZip.Checked then
    Result := tbfZip
  else
    Result := tbfFolder;
end;

procedure TTbExportForm.Prepare(const AEntry, ABaseDir, AName: string; ADualMode: Boolean);
var
  i: Integer;
begin
  FEntry := AEntry;
  FBaseDir := ABaseDir;
  FDualMode := ADualMode;
  FUpdating := True;
  try
    EdtName.Text := AName;
    EdtVersion.Text := '1.0';
    LblNote.Caption := '';
    BtnExport.Enabled := TbCollectBundleFiles(AEntry, ABaseDir, FFiles, FCollectError);
    LstFiles.Items.BeginUpdate;
    try
      LstFiles.Items.Clear;
      for i := 0 to High(FFiles) do
        LstFiles.Items.Add(FFiles[i].Archive);
      if Length(FFiles) = 0 then
        LstFiles.Items.Add(rsTbExportOnlyTheme);
    finally
      LstFiles.Items.EndUpdate;
    end;
    RadFolder.Checked := True;
    RadZip.Checked := False;
    { a zip cannot carry the files: the library would not find them in it }
    RadZip.Enabled := Length(FFiles) = 0;
    if FCollectError <> '' then
      LblNote.Caption := FCollectError
    else if Length(FFiles) > 0 then
      LblNote.Caption := rsTbExportZipRefs;
    if ABaseDir <> '' then
      EdtTarget.Text := IncludeTrailingPathDelimiter(ABaseDir) + AName
    else
      EdtTarget.Text := '';
  finally
    FUpdating := False;
  end;
end;

{ the target follows the format: name.zip for a zip, name for a folder }
procedure TTbExportForm.FormatChange(Sender: TObject);
var
  t: string;
begin
  if FUpdating then Exit;
  t := EdtTarget.Text;
  if t = '' then Exit;
  if ChosenFormat = tbfZip then
  begin
    if not SameText(ExtractFileExt(t), cZipExt) then
      EdtTarget.Text := ExcludeTrailingPathDelimiter(t) + cZipExt;
  end
  else if SameText(ExtractFileExt(t), cZipExt) then
    EdtTarget.Text := ChangeFileExt(t, '');
end;

function TTbExportForm.DoExport(out AError: string): Boolean;
var
  info: TTbBundleInfo;
  target: string;
  answer: TModalResult;
begin
  AError := '';
  Result := False;
  { a reference that cannot go in: Export is disabled -- and a call from anywhere else is
    refused the same way, or the bundle would go out without that file }
  if FCollectError <> '' then
  begin
    AError := FCollectError;
    LblNote.Caption := AError;
    Exit;
  end;
  info.Name := Trim(EdtName.Text);
  info.Author := Trim(EdtAuthor.Text);
  info.Version := Trim(EdtVersion.Text);
  info.DualMode := FDualMode;
  target := Trim(EdtTarget.Text);
  if (ChosenFormat = tbfZip) and FileExists(target) then
  begin
    if Assigned(FOnAsk) then
      answer := FOnAsk(Format(rsTbExportOverwrite, [target]), [mbYes, mbNo])
    else
      answer := mrNo;
    if answer <> mrYes then
      Exit;
  end;
  Result := TbExportBundle(FEntry, FFiles, info, ChosenFormat, target, AError);
  if Result then
    ModalResult := mrOk
  else
    LblNote.Caption := AError;
end;

procedure TTbExportForm.BtnExportClick(Sender: TObject);
var
  err: string;
begin
  DoExport(err);
end;

procedure TTbExportForm.BtnBrowseClick(Sender: TObject);
begin
  if ChosenFormat = tbfFolder then
  begin
    if FBaseDir <> '' then
      DlgFolder.Directory := FBaseDir;
    if DlgFolder.Execute then
      EdtTarget.Text := IncludeTrailingPathDelimiter(DlgFolder.Directory) + Trim(EdtName.Text);
  end
  else
  begin
    DlgZip.DefaultExt := 'zip';
    DlgZip.FileName := Trim(EdtName.Text) + cZipExt;
    if DlgZip.Execute then
      EdtTarget.Text := DlgZip.FileName;
  end;
end;

end.
