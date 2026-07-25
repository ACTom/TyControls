unit umain;

{ Command and grouped button demo: GlyphButton / GlyphContainerButton / SpeedButton (grouped) /
  DropDownButton / MenuButton / ColorButton / ButtonGroup.
  The window (TTyForm + TTyTitleBar), every button and the live theme switcher are designed in
  umain.lfm; the code here is the shared drop-down menu, the drop-down wiring and theme setup only.
  The glyph buttons render a star (★) from the system symbol font; on a real machine an icon .ttf looks better. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, Menus,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.TyLabel, tyControls.ComboBox, tyControls.ToggleSwitch, tyControls.IconFont,
  tyControls.GlyphButtons, tyControls.DropButtons, tyControls.ColorButton,
  tyControls.ButtonGroup, tyControls.Menu;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    Surface: TTyFormSurface;
    ThemeCombo: TTyComboBox;
    LblGlyph: TTyLabel;
    BtnNew: TTyGlyphButton;
    BtnOpen: TTyGlyphContainerButton;
    LblGroup: TTyLabel;
    Speed1: TTySpeedButton;
    Speed2: TTySpeedButton;
    Speed3: TTySpeedButton;
    LblDrop: TTyLabel;
    BtnSave: TTyDropDownButton;
    BtnMore: TTyMenuButton;
    LblColor: TTyLabel;
    BtnColor: TTyColorButton;
    Grp: TTyButtonGroup;
    Icons: TTyIconFont;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
  private
    FMenu: TTyPopupMenu;
    procedure BuildMenu;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

procedure TMainForm.BuildMenu;
  procedure AddItem(const ACaption: string);
  var mi: TMenuItem;
  begin
    mi := TMenuItem.Create(FMenu);
    mi.Caption := ACaption;
    FMenu.Items.Add(mi);
  end;
begin
  FMenu := TTyPopupMenu.Create(Self);
  FMenu.Controller := TyDefaultController;
  AddItem('Save a copy');
  AddItem('Export as PDF');
  AddItem('Print…');
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  i: Integer;
begin
  // Built-in themes are compiled in, so the switcher works without locating a themes/ folder.
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do
    ThemeCombo.Items.Add(names[i]);
  ThemeCombo.ItemIndex := ThemeCombo.Items.IndexOf('default');
  TyDefaultController.ThemeName := 'default';
  ApplyChromeTheme(TyDefaultController);   // theme the window chrome + background

  // The shared pop-up menu is built in code (items added in a loop) and wired to the
  // drop-down / menu buttons designed in the .lfm.
  BuildMenu;
  BtnSave.DropDownMenu := FMenu;
  BtnMore.DropDownMenu := FMenu;
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
