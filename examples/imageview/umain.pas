unit umain;

{ TTyImageView demo -- an image viewer.

  "Open image" picks a file with TTyOpenPictureDialog (preview pane on the right) and loads it
  into TTyImageView. Then: mouse-wheel zoom centered on the cursor, drag to pan, double-click to
  toggle between fit and 100% -- all smoothly animated; the toolbar buttons zoom too. The row of
  checkboxes at the bottom toggles non-destructive filters (grayscale/sharpen/invert/blur): the
  source image is untouched, only the display is recomputed. The zoom percentage is shown live in
  the caption. Everything is BGRA and cross-platform, needing no image assets (you pick the image). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics,
  tyControls.Controller, tyControls.Form, tyControls.TyLabel,
  tyControls.Button, tyControls.CheckBox, tyControls.Divider,
  tyControls.ComboBox, tyControls.ToggleSwitch, tyControls.BuiltinThemes,
  tyControls.ImageView, tyControls.Dialogs.FileDialog;

type
  TMainForm = class(TTyForm)
    Surface: TTyFormSurface;
    TitleBar1: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    ThemeCombo: TTyComboBox;
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
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
  private
    FOpenPic: TTyOpenPictureDialog;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

procedure TMainForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  i: Integer;
begin
  // Built-in themes are compiled in, so the switcher works without locating a themes/ folder.
  TyDefaultController.ThemeName := 'default';
  View.OnZoomChange := @ViewZoomChange;

  FOpenPic := TTyOpenPictureDialog.Create(Self);
  FOpenPic.Title := 'Open picture';
  FOpenPic.InitialDir := ExcludeTrailingPathDelimiter(GetUserDir);

  ApplyChromeTheme(TyDefaultController);

  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do
    ThemeCombo.Items.Add(names[i]);
  ThemeCombo.ItemIndex := ThemeCombo.Items.IndexOf('default');
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
  LblZoom.Caption := Format('Zoom: %.0f%%', [View.Zoom * 100]);
end;

end.
