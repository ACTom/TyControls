unit umain;

{ 文件对话框示例 —— 六个变体全在这:

  普通    TTyOpenDialog / TTySaveDialog          （树+列表+查找范围+过滤+文件名）
  图片    TTyOpenPictureDialog / TTySavePictureDialog   （右侧图片预览）
  预览    TTyOpenPreviewDialog / TTySavePreviewDialog   （右侧图片/文本预览 + OnPreview 自定义）

  「打开」演示多选(Options 含 fdoAllowMultiSelect + fdoFileMustExist),结果里列出全部选中项。
  「保存」演示默认扩展名 + 覆盖确认(fdoOverwritePrompt)。
  「打开预览」挂了一个自定义 OnPreview:遇到没有内建预览器的格式(如 .exe/.zip),交出一段自定义文本
  显示,而不是"无法预览"占位 —— 这就是"不认识的格式用户自己来"。

  六个对话框都是同一个自绘 TTyFileDialogForm 靠标志拼出来的,主题化、跨平台,不需要任何图片资源。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.TyLabel, tyControls.Button,
  tyControls.Memo, tyControls.Divider,
  tyControls.PreviewBox, tyControls.Dialogs.FileDialog;

type
  TMainForm = class(TTyForm)
    TitleBar1: TTyTitleBar;
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
begin
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  home := ExcludeTrailingPathDelimiter(GetUserDir);

  FOpen := TTyOpenDialog.Create(Self);
  FOpen.Title := '打开文件';
  FOpen.Filter := '文本 (*.txt;*.md)|*.txt;*.md|所有文件 (*.*)|*.*';
  FOpen.InitialDir := home;
  FOpen.Options := [fdoFileMustExist, fdoAllowMultiSelect];

  FSave := TTySaveDialog.Create(Self);
  FSave.Title := '保存文件';
  FSave.Filter := '文本 (*.txt)|*.txt|所有文件 (*.*)|*.*';
  FSave.DefaultExt := 'txt';
  FSave.InitialDir := home;
  FSave.Options := [fdoOverwritePrompt];

  FOpenPic := TTyOpenPictureDialog.Create(Self);
  FOpenPic.Title := '打开图片';
  FOpenPic.InitialDir := home;

  FSavePic := TTySavePictureDialog.Create(Self);
  FSavePic.Title := '保存图片';
  FSavePic.DefaultExt := 'png';
  FSavePic.InitialDir := home;

  FOpenPrev := TTyOpenPreviewDialog.Create(Self);
  FOpenPrev.Title := '打开(带预览)';
  FOpenPrev.InitialDir := home;
  FOpenPrev.OnPreview := @PreviewCustom;   { 自定义:处理没有内建预览器的格式 }

  FSavePrev := TTySavePreviewDialog.Create(Self);
  FSavePrev.Title := '保存(带预览)';
  FSavePrev.InitialDir := home;

  ApplyChromeTheme(TyDefaultController);
end;

{ 自定义预览:内建认识图片和常见文本;这里演示接管"不认识"的格式(pkOther,如 .exe/.zip)——
  交出一段自定义文本,而不是让它落到"无法预览"占位。置 AHandled 跳过内建分派。 }
procedure TMainForm.PreviewCustom(Sender: TObject; const AFileName: string;
  APreview: TTyPreviewBox; var AHandled: Boolean);
begin
  if (AFileName = '') or DirectoryExists(AFileName) then Exit;
  if TyPreviewClassify(AFileName) = pkOther then
  begin
    APreview.ShowText(
      '自定义预览(OnPreview)' + LineEnding + LineEnding +
      '文件:' + ExtractFileName(AFileName) + LineEnding +
      '扩展名:' + ExtractFileExt(AFileName) + LineEnding + LineEnding +
      '这个格式没有内建预览器,由应用的 OnPreview 处理。' + LineEnding +
      '真实场景里你可以把它解码成位图(ShowImage)或文本(ShowText)。');
    AHandled := True;
  end;
  { 其它格式不 handled -> 内建:图片 -> 文本 -> "无法预览" }
end;

procedure TMainForm.Report(const ATitle: string; AOk: Boolean; ADlg: TTyCustomFileDialog);
var
  i: Integer;
begin
  if not AOk then
  begin
    ResultMemo.Lines.Add(ATitle + ':(取消)');
    Exit;
  end;
  if ADlg.Files.Count > 1 then
  begin
    ResultMemo.Lines.Add(Format('%s:选中 %d 项', [ATitle, ADlg.Files.Count]));
    for i := 0 to ADlg.Files.Count - 1 do
      ResultMemo.Lines.Add('    ' + ADlg.Files[i]);
  end
  else
    ResultMemo.Lines.Add(ATitle + ':' + ADlg.FileName);
end;

procedure TMainForm.BtnOpenClick(Sender: TObject);
begin
  Report('打开', FOpen.Execute, FOpen);
end;

procedure TMainForm.BtnSaveClick(Sender: TObject);
begin
  Report('保存', FSave.Execute, FSave);
end;

procedure TMainForm.BtnOpenPicClick(Sender: TObject);
begin
  Report('打开图片', FOpenPic.Execute, FOpenPic);
end;

procedure TMainForm.BtnSavePicClick(Sender: TObject);
begin
  Report('保存图片', FSavePic.Execute, FSavePic);
end;

procedure TMainForm.BtnOpenPrevClick(Sender: TObject);
begin
  Report('打开预览', FOpenPrev.Execute, FOpenPrev);
end;

procedure TMainForm.BtnSavePrevClick(Sender: TObject);
begin
  Report('保存预览', FSavePrev.Execute, FSavePrev);
end;

end.
