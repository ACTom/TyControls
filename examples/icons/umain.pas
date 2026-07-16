unit umain;

{ Icons & images demo:
  · TTyImage —— one (code-generated) bitmap shown in Stretch / Proportional / Center modes (works out of the box).
  · TTyIconFont + TTyCharImage —— icon-font structure demo; to actually see a glyph point FontFile at an
    icon .ttf (e.g. FontAwesome) —— see the note label below.
  The window, every control and the live theme switcher are designed in umain.lfm (a TTyForm + TTyTitleBar);
  the code here is theme setup, the code-generated sample bitmap and the glyph colour only. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics,
  tyControls.Types, tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.TyLabel, tyControls.Image, tyControls.IconFont, tyControls.CharImage,
  tyControls.ComboBox, tyControls.ToggleSwitch;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    Surface: TTyFormSurface;
    ThemeCombo: TTyComboBox;
    Cap1: TTyLabel;
    Img1: TTyImage;
    Cap2: TTyLabel;
    Img2: TTyImage;
    Cap3: TTyLabel;
    Img3: TTyImage;
    Icons: TTyIconFont;
    Ch: TTyCharImage;
    Note: TTyLabel;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

{ A small colorful source bitmap drawn in code (so the demo needs no asset file). }
function MakeSampleBitmap: TBitmap;
begin
  Result := TBitmap.Create;
  Result.SetSize(120, 80);
  Result.Canvas.Brush.Color := $E0A060;   // sky
  Result.Canvas.FillRect(0, 0, 120, 80);
  Result.Canvas.Brush.Color := clWhite;    // sun
  Result.Canvas.Pen.Color := clWhite;
  Result.Canvas.Ellipse(10, 8, 40, 38);
  Result.Canvas.Brush.Color := $3B8B4B;    // hill
  Result.Canvas.Pen.Color := $3B8B4B;
  Result.Canvas.Polygon([Point(0, 80), Point(55, 34), Point(120, 80)]);
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  i: Integer;
  Bmp: TBitmap;
begin
  // Built-in themes are compiled in, so the switcher works without locating a themes/ folder.
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do
    ThemeCombo.Items.Add(names[i]);
  ThemeCombo.ItemIndex := ThemeCombo.Items.IndexOf('default');
  TyDefaultController.ThemeName := 'default';
  ApplyChromeTheme(TyDefaultController);   // theme the window chrome + background

  // The sample bitmap is generated in code, so feed it into the three designed images.
  Bmp := MakeSampleBitmap;
  try
    Img1.Picture.Bitmap.Assign(Bmp);
    Img2.Picture.Bitmap.Assign(Bmp);
    Img3.Picture.Bitmap.Assign(Bmp);
  finally
    Bmp.Free;
  end;

  // GlyphColor is an ARGB TTyColor value computed at runtime.
  Ch.GlyphColor := TyRGB($3B, $82, $F6);
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
