program themebuilder;
{ Theme Builder: write a .tycss theme on the left, see the controls wear it on the right.
  Built from the library sources (../../source, ../../designtime) -- it needs no installed
  tycontrols package: lazbuild -B tools/themebuilder/themebuilder.lpi }
{$mode objfpc}{$H+}
uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, LCLTranslator, SysUtils, tbmain;

{ the project resource carries the XP manifest (common controls v6, DPI awareness) }
{$R *.res}

function LangDir: string;
var Dir: string; i: Integer;
begin
  Dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for i := 1 to 8 do
  begin
    if DirectoryExists(Dir + 'languages') then Exit(Dir + 'languages' + PathDelim);
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if Dir = '' then Break;
  end;
  Result := 'languages' + PathDelim;
end;

begin
  RequireDerivedFormResource := True;
  Application.Title := 'Theme Builder';
  Application.Scaled := True;
  Application.Initialize;
  SetDefaultLang('', LangDir);
  TranslateUnitResourceStringsEx('', LangDir, 'tycontrols', 'tyControls.StrConsts');
  Application.CreateForm(TTbMainForm, TbMainForm);
  Application.Run;
end.
