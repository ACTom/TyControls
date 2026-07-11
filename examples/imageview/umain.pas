unit umain;

{ TTyImageView 示例 —— 图片查看器。

  「打开图片」用 TTyOpenPictureDialog(右侧带预览)选一张图,加载进 TTyImageView。
  然后:滚轮以光标为中心缩放、拖拽平移、双击在 适配↔100% 间切换 —— 都带平滑动画;
  也可以用工具栏按钮缩放。底部一排复选框切非破坏性滤镜(灰度/锐化/反相/模糊),源图不变、
  只重算显示。缩放百分比实时显示在标题。全程 BGRA、跨平台,不需要任何图片资源(图自己选)。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics,
  tyControls.Controller, tyControls.Form, tyControls.TyLabel,
  tyControls.Button, tyControls.CheckBox, tyControls.Divider,
  tyControls.ImageView, tyControls.Dialogs.FileDialog;

type
  TMainForm = class(TTyForm)
    TitleBar1: TTyTitleBar;
    BtnOpen:   TTyButton;
    BtnZoomIn: TTyButton;
    BtnZoomOut: TTyButton;
    BtnFit:    TTyButton;
    BtnActual: TTyButton;
    LblZoom:   TTyLabel;
    Div1:      TTyDivider;
    ChkGray:   TTyCheckBox;
    ChkSharpen: TTyCheckBox;
    ChkInvert: TTyCheckBox;
    ChkBlur:   TTyCheckBox;
    View:      TTyImageView;

    procedure FormCreate(Sender: TObject);
    procedure BtnOpenClick(Sender: TObject);
    procedure BtnZoomInClick(Sender: TObject);
    procedure BtnZoomOutClick(Sender: TObject);
    procedure BtnFitClick(Sender: TObject);
    procedure BtnActualClick(Sender: TObject);
    procedure ChkGrayChange(Sender: TObject);
    procedure ChkSharpenChange(Sender: TObject);
    procedure ChkInvertChange(Sender: TObject);
    procedure ChkBlurChange(Sender: TObject);
    procedure ViewZoomChange(Sender: TObject);
  private
    FOpenPic: TTyOpenPictureDialog;
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
begin
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');
  View.OnZoomChange := @ViewZoomChange;

  FOpenPic := TTyOpenPictureDialog.Create(Self);
  FOpenPic.Title := '打开图片';
  FOpenPic.InitialDir := ExcludeTrailingPathDelimiter(GetUserDir);

  ApplyChromeTheme(TyDefaultController);
end;

procedure TMainForm.BtnOpenClick(Sender: TObject);
begin
  if FOpenPic.Execute then
    View.LoadFromFile(FOpenPic.FileName);
end;

procedure TMainForm.BtnZoomInClick(Sender: TObject);  begin View.ZoomIn;      end;
procedure TMainForm.BtnZoomOutClick(Sender: TObject); begin View.ZoomOut;     end;
procedure TMainForm.BtnFitClick(Sender: TObject);     begin View.ZoomToFit;   end;
procedure TMainForm.BtnActualClick(Sender: TObject);  begin View.ZoomToActual; end;

procedure TMainForm.ChkGrayChange(Sender: TObject);    begin View.Grayscale := ChkGray.Checked;   end;
procedure TMainForm.ChkSharpenChange(Sender: TObject); begin View.Sharpen := ChkSharpen.Checked;  end;
procedure TMainForm.ChkInvertChange(Sender: TObject);  begin View.Invert := ChkInvert.Checked;    end;

procedure TMainForm.ChkBlurChange(Sender: TObject);
begin
  { non-destructive: radius 0 = off }
  if ChkBlur.Checked then View.BlurRadius := 4 else View.BlurRadius := 0;
end;

procedure TMainForm.ViewZoomChange(Sender: TObject);
begin
  LblZoom.Caption := Format('缩放:%.0f%%', [View.Zoom * 100]);
end;

end.
