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
    Rich:   TTyHtmlLabel;
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

  Rich.OnLinkClick := @RichLinkClick;
  Rich.Html :=
    '<b>TyControls</b> is a set of <i>custom-drawn</i> Lazarus controls,' +
    'Themed, cross-platform.<br>' +
    'This label supports <u>underline</u>, <s>strikethrough</s>,' +
    '<font color=#c0392b>red</font> and <font size=16>large text</font>,' +
    'and <a href="https://github.com/ACTom/TyControls">a clickable link</a>.<br>' +
    'Entities work too: &lt;tag&gt; &amp; &quot;quotes&quot;.';

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
  LblStatus.Caption := 'Clicked link:' + AHref;
end;

end.
