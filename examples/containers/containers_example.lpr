program containers_example;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, umain, LCLTranslator, SysUtils;

{ ac2363. Without this the project resource -- which is where the XP manifest lives -- is
  never linked, so `UseXPManifest` in the .lpi had no effect at all: no common-controls v6,
  and no DPI awareness. This example was the only one of the two flipped to PerMonitorV2
  that lacked the line (demo.lpr has always had it), and the flip would otherwise have been
  cosmetic. Verified by searching the built .exe for the <dpiAwareness> element. }
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
  Application.Scaled := True;
  Application.Initialize;
  SetDefaultLang('', LangDir);
  TranslateUnitResourceStringsEx('', LangDir, 'tycontrols', 'tyControls.StrConsts');
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
