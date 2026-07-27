unit umain;

{ TTyHtmlLabel demo -- inline HTML-subset rich text + links. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.TyLabel,
  tyControls.HtmlLabel, tyControls.BuiltinThemes, tyControls.ComboBox, tyControls.ToggleSwitch;

type
  TMainForm = class(TTyForm)
    Surface: TTyFormSurface;
    TitleBar1: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    ThemeCombo: TTyComboBox;
    LblHeadMarkup:   TTyLabel;
    Rich:   TTyHtmlLabel;
    LblHeadNoWrap:   TTyLabel;
    RichNoWrap:      TTyHtmlLabel;
    LblHeadAutoSize: TTyLabel;
    RichAuto:        TTyHtmlLabel;
    LblStatus: TTyLabel;

    procedure FormCreate(Sender: TObject);
    procedure RichLinkClick(Sender: TObject; const AHref: string);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
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
  TyDefaultController.ThemeName := 'default';

  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do
    ThemeCombo.Items.Add(names[i]);
  ThemeCombo.ItemIndex := ThemeCombo.Items.IndexOf('default');

  // Html and OnLinkClick are design-time properties: every label's markup and the link
  // handler are set in umain.lfm, so nothing about the rich text is wired up here.

  ApplyChromeTheme(TyDefaultController);
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

procedure TMainForm.RichLinkClick(Sender: TObject; const AHref: string);
begin
  // AHref is whatever the clicked <a href="..."> carried -- the two links in Rich
  // report two different URLs through this one handler.
  LblStatus.Caption := 'Clicked link: ' + AHref;
end;

end.
