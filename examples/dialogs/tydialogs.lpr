program tydialogs;
{$mode objfpc}{$H+}
uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, SysUtils, LCLTranslator,
  mainform;

{$R *.res}

// Search upward from the exe for a 'languages' folder holding the tydialogs.<lang>.po catalogs (robust
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
  // Force Chinese BEFORE any form (or dialog) is created, so the LRSTranslator translates captions
  // during streaming and the runtime resourcestrings resolve to zh_CN. We pass 'zh_CN' explicitly
  // (not '' = autodetect) so a MessageBox shows 确定/取消 regardless of the host OS locale.
  SetDefaultLang('zh_CN', LangDir);
  // SetDefaultLang only loads languages/tydialogs.<lang>.po (derived from the exe name). The tyControls
  // package's own resourcestrings (dialog buttons / type titles etc.) live in a separate catalog and
  // need their own load, or they stay at their English msgids no matter what UI language is active.
  // The catalog stem is DOT-FREE ('tycontrols'); the real unit name is the last arg.
  TranslateUnitResourceStringsEx('zh_CN', LangDir, 'tycontrols', 'tyControls.StrConsts');
  Application.CreateForm(TDialogsMainForm, DialogsMainForm);
  Application.Run;
end.
