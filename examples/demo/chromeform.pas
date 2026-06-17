unit chromeform;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Forms, Graphics,
  tyControls.Controller, tyControls.TyLabel, tyControls.Form;
type
  TChromeForm = class(TTyForm)
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
var
  Dir: string;
  i: Integer;
begin
  // 从 exe 所在目录向上逐级查找 themes/，对以下位置均健壮：
  //   <repo>/examples/demo/demo（工程目录）
  //   <repo>/examples/demo/lib/<cpu>-<os>/demo（lazbuild 默认输出）
  //   <repo>/examples/demo/demo.app/Contents/MacOS/demo（macOS 包）
  Dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for i := 1 to 8 do
  begin
    if DirectoryExists(Dir + 'themes') then
      Exit(Dir + 'themes' + PathDelim);
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if Dir = '' then Break;
  end;
  Result := 'themes' + PathDelim; // 兜底：相对当前目录
end;

procedure TChromeForm.FormCreate(Sender: TObject);
var
  ThemeFile: string;
begin
  // 仅当解析到的主题文件存在时才加载，避免从构建输出目录运行时
  // 因找不到 themes/ 而抛出 EFOpenError；缺失时回退到内置皮肤。
  ThemeFile := ThemeDir + 'showcase.tycss';
  if FileExists(ThemeFile) then
  begin
    Controller.LoadTheme(ThemeFile);
    // Window chrome + backdrop follow the theme via the TyForm token.
    ApplyChromeTheme(Controller);
  end;
  if TitleBar <> nil then TitleBar.Caption := 'Custom Chrome Window';
  Controller.Changed;
end;

end.
