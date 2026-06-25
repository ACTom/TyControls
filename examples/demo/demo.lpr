program demo;
{$mode objfpc}{$H+}
uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, SysUtils, LCLTranslator,
  mainform, chromeform;

{$R *.res}

// Search upward from the exe for a 'languages' folder holding the demo.<lang>.po catalogs (robust
// to running from the project dir, lib/<cpu>-<os>/, or a macOS .app bundle).
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
  Application.Scaled:=True;
  Application.Initialize;
  // Apply the OS UI language BEFORE any form is created, so the LRSTranslator translates captions
  // during streaming (the reliable path — not runtime re-translation of an already-shown form).
  // SetDefaultLang('') autodetects the OS locale (or a --lang= param) + loads languages/demo.<lang>.po.
  SetDefaultLang('', LangDir);
  Application.CreateForm(TDemoMainForm, DemoMainForm);
  Application.CreateForm(TChromeForm, ChromeFormWnd);
  Application.Run;
end.
