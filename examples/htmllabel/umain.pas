unit umain;

{ TTyHtmlLabel 示例 —— 行内 HTML 子集富文本 + 链接。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.TyLabel,
  tyControls.HtmlLabel;

type
  TMainForm = class(TTyForm)
    TitleBar1: TTyTitleBar;
    Rich:   TTyHtmlLabel;
    LblStatus: TTyLabel;

    procedure FormCreate(Sender: TObject);
    procedure RichLinkClick(Sender: TObject; const AHref: string);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

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

procedure TMainForm.FormCreate(Sender: TObject);
begin
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

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

procedure TMainForm.RichLinkClick(Sender: TObject; const AHref: string);
begin
  LblStatus.Caption := '点击了链接:' + AHref;
end;

end.
