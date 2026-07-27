unit umain;

{ Command and grouped button demo: GlyphButton / GlyphContainerButton / SpeedButton (grouped) /
  DropDownButton / MenuButton / ColorButton / ButtonGroup.
  The window (TTyForm + TTyTitleBar), every button and the live theme switcher are designed in
  umain.lfm; the code here is the shared drop-down menu, the drop-down wiring and theme setup only.
  The glyph buttons render a star (★) from the system symbol font; on a real machine an icon .ttf looks better.
  The bottom row answers that: BtnImg takes its glyph from a TTyImageCollection (Images/ImageName win over
  IconFont/GlyphName) so the icon is identical on every OS — the bitmap is drawn in code because a BGRA
  image cannot be expressed in the .lfm. Every button reports what it did in LblStatus. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, Menus, BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.TyLabel, tyControls.ComboBox, tyControls.ToggleSwitch, tyControls.IconFont,
  tyControls.ImageCollection, tyControls.GlyphButtons, tyControls.DropButtons,
  tyControls.ColorButton, tyControls.ButtonGroup, tyControls.Menu;

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
    LblGroupHint: TTyLabel;
    LblDrop: TTyLabel;
    BtnSave: TTyDropDownButton;
    BtnMore: TTyMenuButton;
    LblColor: TTyLabel;
    BtnColor: TTyColorButton;
    Grp: TTyButtonGroup;
    LblSwatch: TTyLabel;
    BtnColorSwatch: TTyColorButton;
    LblMulti: TTyLabel;
    GrpMulti: TTyButtonGroup;
    LblImg: TTyLabel;
    BtnImg: TTyGlyphButton;
    BtnBigGlyph: TTyGlyphButton;
    LblStatus: TTyLabel;
    Icons: TTyIconFont;
    Pics: TTyImageCollection;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure SaveClicked(Sender: TObject);
    procedure SaveDropDown(Sender: TObject);
    procedure ColorChanged(Sender: TObject);
    procedure GrpChange(Sender: TObject);
    procedure GrpMultiChange(Sender: TObject);
  private
    FMenu: TTyPopupMenu;
    { BtnSave gets its OWN menu so OnDropDown can rebuild it on every drop without
      also rewriting the static menu BtnMore shows. }
    FSaveMenu: TTyPopupMenu;
    procedure BuildMenu;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

{ Append one plain item to AMenu (the menu owns it, so a later Items.Clear frees it). }
procedure AddMenuItem(AMenu: TTyPopupMenu; const ACaption: string);
var mi: TMenuItem;
begin
  mi := TMenuItem.Create(AMenu);
  mi.Caption := ACaption;
  AMenu.Items.Add(mi);
end;

{ Draw a 32px floppy-disk "save" icon into the collection. The glyph is tinted to the
  button's text colour, so it is authored as an alpha MASK: an opaque body with the
  shutter and the label punched out (dmSet writes transparency instead of blending). }
procedure BuildSaveIcon(AColl: TTyImageCollection; const AName: string);
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(32, 32, BGRAPixelTransparent);
  try
    bmp.FillRoundRectAntialias(2, 2, 30, 30, 4, 4, BGRA(0, 0, 0, 255));   // disk body
    bmp.FillRect(11, 4, 21, 13, BGRAPixelTransparent, dmSet);             // shutter cut-out
    bmp.FillRect(8, 17, 24, 28, BGRAPixelTransparent, dmSet);             // label cut-out
    AColl.AddBitmap(AName, bmp);
  finally
    bmp.Free;
  end;
end;

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
  BtnMore.DropDownMenu := FMenu;

  // BtnSave's menu is rebuilt from scratch by OnDropDown every time the arrow zone is
  // clicked, so it needs a menu of its own (BtnMore keeps the static one above).
  FSaveMenu := TTyPopupMenu.Create(Self);
  FSaveMenu.Controller := TyDefaultController;
  BtnSave.DropDownMenu := FSaveMenu;

  // The cross-platform image glyph: a BGRA bitmap can't live in the .lfm, so draw it
  // into the designed collection here. BtnImg's Images/ImageName then win over IconFont.
  BuildSaveIcon(Pics, 'save');

  // ARGB TTyColor values are computed at runtime (the .lfm can only carry a raw integer).
  BtnColorSwatch.SelectedColor := TyRGB($16, $A3, $4A);   // green swatch
  BtnBigGlyph.GlyphColor := TyRGB($E1, $1D, $48);         // rose glyph, caption stays themed
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

procedure TMainForm.SaveClicked(Sender: TObject);
begin
  // A split button's caption half is a normal button: this is the primary action.
  // A click in the arrow zone never reaches here -- it drops the menu instead.
  LblStatus.Caption := 'Save: primary half clicked (the arrow half opens the menu)';
end;

procedure TMainForm.SaveDropDown(Sender: TObject);
begin
  // OnDropDown fires just BEFORE the menu pops, so the menu can be rebuilt each time.
  // The timestamped last item makes that visible: drop it twice and the time changes.
  FSaveMenu.Items.Clear;
  AddMenuItem(FSaveMenu, 'Save a copy');
  AddMenuItem(FSaveMenu, 'Export as PDF');
  AddMenuItem(FSaveMenu, 'Snapshot ' + FormatDateTime('hh:nn:ss', Now));
end;

procedure TMainForm.ColorChanged(Sender: TObject);
begin
  // Fires only when the dialog was accepted AND the colour really changed --
  // a programmatic SelectedColor write (see FormCreate) never lands here.
  LblStatus.Caption := 'Colour changed to ' + TyColorHex(BtnColor.SelectedColor);
end;

procedure TMainForm.GrpChange(Sender: TObject);
begin
  if Grp.ItemIndex >= 0 then
    LblStatus.Caption := 'ButtonGroup: ' + Grp.Items[Grp.ItemIndex]
  else
    LblStatus.Caption := 'ButtonGroup: nothing selected';
end;

procedure TMainForm.GrpMultiChange(Sender: TObject);
var
  i: Integer;
  picked: string;
begin
  // MultiSelect has no ItemIndex: ask each segment whether its bit is set.
  picked := '';
  for i := 0 to GrpMulti.Count - 1 do
    if GrpMulti.IsSelected(i) then
    begin
      if picked <> '' then picked := picked + ', ';
      picked := picked + GrpMulti.Items[i];
    end;
  if picked = '' then picked := 'none';
  LblStatus.Caption := 'MultiSelect group: ' + picked;
end;

end.
