unit umain;

{ TTyLabel demo (TTyForm + TTyTitleBar):
  Showcases the core published features of TTyLabel --
    - Alignment: taLeftJustify / taCenter / taRightJustify horizontal alignment
    - Layout: tlTop / tlCenter / tlBottom vertical alignment (within a fixed height)
    - WordWrap: long text auto-wraps at spaces to fit the control width
    - AutoSize: on = shrink/grow to fit the text; off = fixed bounds
    - Transparent: True = transparent background; False = filled with the theme panel color
    - FocusControl + & mnemonic: Alt+letter sends focus to the associated TTyEdit
    - AutoSize + WordWrap together: the label keeps its width and re-heights itself to the
      wrapped text (the window is resizable, so widening it re-wraps and re-fits the box)
    - OnClick: a label raises it like any other control
    - StyleOverride: per-instance CSS, the only way to make ONE label look different --
      font size/weight come from the THEME (TyResolveFontSize consults the theme before
      Font.Size), so LblHead overrides font-size/font-weight to read as a heading and
      LblAccent overrides colour with var(--accent), which still tracks the theme.
  The Layout / auto-wrap boxes also use StyleOverride for their frame: the themed TyLabel
  background is fully transparent, so without it Transparent=False would draw no visible box.
  The window, every label and the live theme switcher are designed in umain.lfm (a TTyForm +
  TTyTitleBar); the code here is theme setup + the click counter only. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, Graphics,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.TyLabel, tyControls.Edit, tyControls.ComboBox, tyControls.ToggleSwitch;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    Surface: TTyFormSurface;
    ThemeCombo: TTyComboBox;
    LblHead: TTyLabel;
    LblLeft: TTyLabel;
    LblCenter: TTyLabel;
    LblRight: TTyLabel;
    LblFilled: TTyLabel;
    LblAuto: TTyLabel;
    LblWrap: TTyLabel;
    EdName: TTyEdit;
    LblFocus: TTyLabel;
    LblLayoutHead: TTyLabel;
    LblLayoutTop: TTyLabel;
    LblLayoutCenter: TTyLabel;
    LblLayoutBottom: TTyLabel;
    LblWrapAutoHead: TTyLabel;
    LblWrapAuto: TTyLabel;
    LblClick: TTyLabel;
    LblAccent: TTyLabel;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure LblClickClick(Sender: TObject);
  private
    FClicks: Integer;   // how many times LblClick has been clicked
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
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do
    ThemeCombo.Items.Add(names[i]);
  ThemeCombo.ItemIndex := ThemeCombo.Items.IndexOf('default');
  TyDefaultController.ThemeName := 'default';
  ApplyChromeTheme(TyDefaultController);   // theme the window chrome + background
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

{ A label is a full control, not decoration: TTyLabel.Click raises OnClick first and only then
  hands focus to FocusControl -- so a label can be a clickable target on its own. }
procedure TMainForm.LblClickClick(Sender: TObject);
begin
  Inc(FClicks);
  LblClick.Caption := 'Clicked ' + IntToStr(FClicks) +
    ' time(s) - labels raise OnClick too';
end;

end.
