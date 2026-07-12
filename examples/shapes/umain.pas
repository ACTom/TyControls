unit umain;

{ Phase-9 vector shape example (TTyShape / TTyStarShape / TTyArrow).

  All controls are laid out in the designer (umain.lfm) and streamed in at runtime by TTyForm;
  the code only does the two things the .lfm can't express:
  load a theme, and wire the trackbars to the shape properties.

  The fill / stroke of all three controls come from the resolved TyPanel style, so:
    - switch theme -> shapes without a StyleOverride recolor as a whole;
    - shapes with a StyleOverride follow their own rules (literal colors, or theme variables like var(--accent)). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.TyLabel, tyControls.Divider,
  tyControls.Button, tyControls.TrackBar, tyControls.ComboBox,
  tyControls.Shape, tyControls.StarShape, tyControls.Arrow;

type
  TMainForm = class(TTyForm)
    TitleBar1: TTyTitleBar;
    ThemeCombo: TTyComboBox;

    DivKinds: TTyDivider;
    ShRect: TTyShape;
    ShRound: TTyShape;
    ShSquare: TTyShape;
    ShEllipse: TTyShape;
    ShCircle: TTyShape;
    ShTriangle: TTyShape;
    ShDiamond: TTyShape;
    ShLine: TTyShape;
    LblRect: TTyLabel;
    LblRound: TTyLabel;
    LblSquare: TTyLabel;
    LblEllipse: TTyLabel;
    LblCircle: TTyLabel;
    LblTriangle: TTyLabel;
    LblDiamond: TTyLabel;
    LblLine: TTyLabel;

    DivStyle: TTyDivider;
    ShOver1: TTyShape;
    ShOver2: TTyShape;
    ShNoBorder: TTyShape;
    ShZeroWidth: TTyShape;
    ShThick: TTyShape;
    ShLineThick: TTyShape;
    LblOver1: TTyLabel;
    LblOver2: TTyLabel;
    LblNoBorder: TTyLabel;
    LblZeroWidth: TTyLabel;
    LblThick: TTyLabel;
    LblLineThick: TTyLabel;

    DivStar: TTyDivider;
    StarBig: TTyStarShape;
    LblPoints: TTyLabel;
    TrackPoints: TTyTrackBar;
    LblInner: TTyLabel;
    TrackInner: TTyTrackBar;
    LblStarHint: TTyLabel;

    DivArrow: TTyDivider;
    ArrRight: TTyArrow;
    ArrLeft: TTyArrow;
    ArrUp: TTyArrow;
    ArrDown: TTyArrow;
    LblArrRight: TTyLabel;
    LblArrLeft: TTyLabel;
    LblArrUp: TTyLabel;
    LblArrDown: TTyLabel;
    ArrowBig: TTyArrow;
    LblHead: TTyLabel;
    TrackHead: TTyTrackBar;
    LblShaft: TTyLabel;
    TrackShaft: TTyTrackBar;

    DivTheme: TTyDivider;
    BtnLight: TTyButton;
    BtnDark: TTyButton;
    BtnGreen: TTyButton;
    LblThemeHint: TTyLabel;

    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure TrackPointsChange(Sender: TObject);
    procedure TrackInnerChange(Sender: TObject);
    procedure TrackHeadChange(Sender: TObject);
    procedure TrackShaftChange(Sender: TObject);
    procedure BtnLightClick(Sender: TObject);
    procedure BtnDarkClick(Sender: TObject);
    procedure BtnGreenClick(Sender: TObject);
  private
    procedure UseTheme(const AFile: string);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

{ Walk up from the exe location looking for themes/, so the theme is found both when
  double-clicking the exe and when running from the repo root. }
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

procedure TMainForm.UseTheme(const AFile: string);
begin
  // Global default controller: controls with Controller=nil fall back to it via ActiveController.
  TyDefaultController.LoadTheme(ThemesDir + AFile);
  ApplyChromeTheme(TyDefaultController);   // title bar + window rounded corners/shadow
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  i: Integer;
begin
  // Built-in themes are compiled in, so the switcher works without locating a themes/ folder.
  TyRegisterBuiltinThemes;
  TyDefaultController.ThemeName := 'default';
  ApplyChromeTheme(TyDefaultController);   // title bar + window rounded corners/shadow
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

procedure TMainForm.TrackPointsChange(Sender: TObject);
begin
  StarBig.Points := TrackPoints.Position;
  LblPoints.Caption := Format('角数 Points = %d', [StarBig.Points]);
end;

procedure TMainForm.TrackInnerChange(Sender: TObject);
begin
  StarBig.InnerRatio := TrackInner.Position / 100;
  LblInner.Caption := Format('内半径比 InnerRatio = %.2f', [StarBig.InnerRatio]);
end;

procedure TMainForm.TrackHeadChange(Sender: TObject);
begin
  ArrowBig.HeadRatio := TrackHead.Position / 100;
  LblHead.Caption := Format('头部占长度 HeadRatio = %.2f', [ArrowBig.HeadRatio]);
end;

procedure TMainForm.TrackShaftChange(Sender: TObject);
begin
  ArrowBig.ShaftRatio := TrackShaft.Position / 100;
  LblShaft.Caption := Format('箭杆占宽度 ShaftRatio = %.2f', [ArrowBig.ShaftRatio]);
end;

procedure TMainForm.BtnLightClick(Sender: TObject);
begin
  UseTheme('light.tycss');
end;

procedure TMainForm.BtnDarkClick(Sender: TObject);
begin
  UseTheme('dark.tycss');
end;

procedure TMainForm.BtnGreenClick(Sender: TObject);
begin
  UseTheme('green.tycss');
end;

end.
