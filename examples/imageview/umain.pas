unit umain;

{ TTyImageView demo -- an image viewer.

  "Open image" picks a file with TTyOpenPictureDialog (preview pane on the right) and loads it
  into TTyImageView. Then: mouse-wheel zoom centered on the cursor, drag to pan, double-click to
  toggle between fit and 100% -- all smoothly animated; the toolbar buttons zoom too. The row of
  checkboxes toggles non-destructive filters (grayscale/sharpen/invert/blur/tint): the source
  image is untouched, only the display is recomputed. The zoom percentage is shown live, clamped
  to the ZoomMin/ZoomMax set in the .lfm, and the second row toggles AnimationDuration and AutoFit
  so both halves of each knob can be compared. Three content paths are shown: Picture (the startup
  image, built here so a design-time Picture in the .lfm streams the same way), LoadFromFile, and
  AssignBitmap (a runtime-drawn TBGRABitmap, no lossy TPicture round-trip); Clear empties the view.
  Everything is BGRA and cross-platform, needing no image assets (you pick the image). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, Graphics,
  BGRABitmap, BGRABitmapTypes, BGRAGradientScanner,
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
    BtnGenerated: TTyButton;
    BtnClear:  TTyButton;
    LblZoom:   TTyLabel;
    Div1:      TTyDivider;
    ChkGray:   TTyCheckBox;
    ChkSharpen: TTyCheckBox;
    ChkInvert: TTyCheckBox;
    ChkBlur:   TTyCheckBox;
    ChkTint:   TTyCheckBox;
    LblTint:   TTyLabel;
    Div2:      TTyDivider;
    ChkAnim:   TTyCheckBox;
    ChkAutoFit: TTyCheckBox;
    LblView:   TTyLabel;
    View:      TTyImageView;

    procedure FormCreate(Sender: TObject);
    procedure BtnOpenClick(Sender: TObject);
    procedure BtnZoomInClick(Sender: TObject);
    procedure BtnZoomOutClick(Sender: TObject);
    procedure BtnFitClick(Sender: TObject);
    procedure BtnActualClick(Sender: TObject);
    procedure BtnGeneratedClick(Sender: TObject);
    procedure BtnClearClick(Sender: TObject);
    procedure ChkGrayChange(Sender: TObject);
    procedure ChkSharpenChange(Sender: TObject);
    procedure ChkInvertChange(Sender: TObject);
    procedure ChkBlurChange(Sender: TObject);
    procedure ChkTintChange(Sender: TObject);
    procedure ChkAnimChange(Sender: TObject);
    procedure ChkAutoFitChange(Sender: TObject);
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

resourcestring
  rsOpenPicture = 'Open picture';
  rsZoomNone    = 'Zoom: —';
  rsZoomFmt     = 'Zoom: %.0f%%   (clamped 10%%..800%%)';

{ The startup picture. Plain GDI on a TBitmap, because it is fed in through the published
  Picture property -- the one path the Object Inspector and .lfm streaming also use. }
function MakeStartupBitmap: TBitmap;
begin
  Result := TBitmap.Create;
  Result.SetSize(420, 280);
  Result.Canvas.Brush.Color := $C08040;    // TColor is $00BBGGRR -- this is a dusk blue
  Result.Canvas.FillRect(0, 0, 420, 280);
  Result.Canvas.Brush.Color := clWhite;    // sun
  Result.Canvas.Pen.Color := clWhite;
  Result.Canvas.Ellipse(292, 30, 372, 110);
  Result.Canvas.Brush.Color := $3B8B4B;    // far ridge
  Result.Canvas.Pen.Color := $3B8B4B;
  Result.Canvas.Polygon([Point(-10, 280), Point(140, 110), Point(300, 280)]);
  Result.Canvas.Brush.Color := $2A6438;    // near ridge
  Result.Canvas.Pen.Color := $2A6438;
  Result.Canvas.Polygon([Point(170, 280), Point(320, 150), Point(440, 280)]);
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  i: Integer;
  bmp: TBitmap;
begin
  // Built-in themes are compiled in, so the switcher works without locating a themes/ folder.
  TyDefaultController.ThemeName := 'default';
  View.OnZoomChange := @ViewZoomChange;

  { Picture is the only published content property, so a picture dropped in at design time
    streams straight into it. Filling it here means the window opens on an auto-fitted image
    instead of an empty matte -- and the zoom readout has something to report. }
  bmp := MakeStartupBitmap;
  try
    View.Picture.Bitmap.Assign(bmp);
  finally
    bmp.Free;
  end;

  FOpenPic := TTyOpenPictureDialog.Create(Self);
  FOpenPic.Title := rsOpenPicture;
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

procedure TMainForm.BtnGeneratedClick(Sender: TObject);
var
  bmp: TBGRABitmap;
  grad: TBGRAGradientScanner;
  i: Integer;
begin
  { AssignBitmap hands a runtime-drawn TBGRABitmap straight to the view's source, skipping the
    TPicture/TBitmap round-trip that can flatten a generated image to black. The view keeps its
    own copy, so this bitmap is still ours to free. The hairline grid is deliberate: it is what
    makes 800% zoom, Sharpen and Blur actually visible. }
  bmp := TBGRABitmap.Create(640, 420, BGRA(255, 255, 255, 255));
  try
    grad := TBGRAGradientScanner.Create(BGRA(28, 58, 108, 255), BGRA(206, 226, 248, 255),
      gtLinear, PointF(0, 0), PointF(0, 420));
    try
      bmp.FillRect(0, 0, 640, 420, grad, dmSet);
    finally
      grad.Free;
    end;
    for i := 1 to 15 do
      bmp.FillRectAntialias(i * 40, 0, i * 40 + 1, 420, BGRA(255, 255, 255, 80));
    for i := 1 to 9 do
      bmp.FillRectAntialias(0, i * 42, 640, i * 42 + 1, BGRA(255, 255, 255, 80));
    bmp.FillEllipseAntialias(478, 118, 72, 72, BGRA(255, 202, 74, 235));
    bmp.FillPolyAntialias([PointF(-10, 420), PointF(156, 246), PointF(330, 420)],
      BGRA(22, 92, 72, 210));
    bmp.FillPolyAntialias([PointF(206, 420), PointF(418, 210), PointF(660, 420)],
      BGRA(12, 56, 48, 235));
    View.AssignBitmap(bmp);
  finally
    bmp.Free;
  end;
end;

procedure TMainForm.BtnClearClick(Sender: TObject);
begin
  { Empty state: no source at all. The view keeps painting its themed matte -- no crash, and
    the wheel/drag/double-click paths all no-op. Clear does not fire OnZoomChange. }
  View.Clear;
  LblZoom.Caption := rsZoomNone;
end;

procedure TMainForm.ChkGrayChange(Sender: TObject);    begin View.Grayscale := ChkGray.Checked;   end;
procedure TMainForm.ChkSharpenChange(Sender: TObject); begin View.Sharpen := ChkSharpen.Checked;  end;
procedure TMainForm.ChkInvertChange(Sender: TObject);  begin View.Invert := ChkInvert.Checked;    end;

procedure TMainForm.ChkBlurChange(Sender: TObject);
begin
  { non-destructive: radius 0 = off }
  if ChkBlur.Checked then View.BlurRadius := 4 else View.BlurRadius := 0;
end;

procedure TMainForm.ChkTintChange(Sender: TObject);
begin
  { The pipeline's fifth and last stage: TintColor laid over the result at TintAmount percent.
    TintColor is a plain LCL TColor (not a TTyColor), so a normal RGB value is what it wants. }
  if ChkTint.Checked then
  begin
    View.TintColor := RGBToColor($E0, $A0, $60);
    View.TintAmount := 35;
  end
  else
    View.TintAmount := 0;   { amount 0 = off; the colour can stay }
end;

procedure TMainForm.ChkAnimChange(Sender: TObject);
begin
  { 180 ms eased versus 0 = snap. Uncheck it and hit +/- or double-click to feel the difference. }
  if ChkAnim.Checked then View.AnimationDuration := 180 else View.AnimationDuration := 0;
end;

procedure TMainForm.ChkAutoFitChange(Sender: TObject);
begin
  { On (the default): every load and every window resize re-fits the image. Off: the current
    zoom survives a resize -- which is what you want once the user has zoomed in somewhere.
    Zooming or panning by hand clears the flag on its own, so this box can lag the real state. }
  View.AutoFit := ChkAutoFit.Checked;
end;

procedure TMainForm.ViewZoomChange(Sender: TObject);
begin
  { ZoomMin/ZoomMax are set on the view in umain.lfm; the wheel and the buttons both stop there. }
  LblZoom.Caption := Format(rsZoomFmt, [View.Zoom * 100]);
end;

end.
