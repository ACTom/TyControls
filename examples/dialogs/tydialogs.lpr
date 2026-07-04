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
  // during streaming and the runtime resourcestrings resolve to the OS language. Pass '' =
  // AUTODETECT the host OS locale (follow the system; do NOT force a language).
  SetDefaultLang('', LangDir);
  // SetDefaultLang only loads languages/tydialogs.<lang>.po (derived from the exe name). The tyControls
  // package's own resourcestrings (dialog buttons / type titles etc.) live in a separate catalog and
  // need their own load, or they stay at their English msgids no matter what UI language is active.
  // The catalog stem is DOT-FREE ('tycontrols'); the real unit name is the last arg. '' autodetects,
  // and TranslateUnitResourceStrings tries BOTH the detected lang and its 2-letter fallback — so a
  // zh_CN OS resolving to either 'zh_CN' or 'zh' finds a Chinese catalog (both .po files are shipped).
  TranslateUnitResourceStringsEx('', LangDir, 'tycontrols', 'tyControls.StrConsts');
  Application.CreateForm(TDialogsMainForm, DialogsMainForm);
  Application.Run;
end.
