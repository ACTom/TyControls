unit umain;

{ TTyHtmlLabel demo -- inline HTML-subset rich text + links. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.TyLabel,
  tyControls.HtmlLabel, tyControls.BuiltinThemes, tyControls.ComboBox;

type
  TMainForm = class(TTyForm)
    TitleBar1: TTyTitleBar;
    ThemeCombo: TTyComboBox;
    Rich:   TTyHtmlLabel;
    LblStatus: TTyLabel;

    procedure FormCreate(Sender: TObject);
    procedure RichLinkClick(Sender: TObject; const AHref: string);
    procedure ThemeComboChange(Sender: TObject);
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
    '<b>TyControls</b> 是一套 <i>自绘</i> 的 Lazarus 控件库,' +
    '主题化、跨平台。<br>' +
    '这个标签支持 <u>下划线</u>、<s>删除线</s>、' +
    '<font color=#c0392b>红色</font> 与 <font size=16>大字号</font>,' +
    '以及 <a href="https://github.com/ACTom/TyControls">可点击的链接</a>。<br>' +
    '实体也可以:&lt;tag&gt; &amp; &quot;引号&quot;。';

  ApplyChromeTheme(TyDefaultController);
end;

procedure TMainForm.ThemeComboChange(Sender: TObject);
begin
  if ThemeCombo.ItemIndex < 0 then Exit;
  TyDefaultController.ThemeName := ThemeCombo.Items[ThemeCombo.ItemIndex];
  ApplyChromeTheme(TyDefaultController);   // re-theme the shell on every skin change
end;

procedure TMainForm.RichLinkClick(Sender: TObject; const AHref: string);
begin
  LblStatus.Caption := '点击了链接:' + AHref;
end;

end.
