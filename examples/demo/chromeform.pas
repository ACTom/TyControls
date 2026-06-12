unit chromeform;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Forms,
  tyControls.Controller, tyControls.TyLabel, tyControls.Form;
type
  TChromeForm = class(TForm)
    Chrome: TTyFormChrome;
    Controller: TTyStyleController;
    LblInfo: TTyLabel;
    procedure FormCreate(Sender: TObject);
  private
    function ThemeDir: string;
  end;
var
  ChromeFormWnd: TChromeForm;
implementation
{$R *.lfm}

function TChromeForm.ThemeDir: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + '..' +
    PathDelim + 'themes' + PathDelim;
end;

procedure TChromeForm.FormCreate(Sender: TObject);
begin
  Controller.LoadTheme(ThemeDir + 'showcase.tycss');
  Chrome.TitleBar.Caption := 'Custom Chrome Window';
  Controller.Changed;
end;

end.
