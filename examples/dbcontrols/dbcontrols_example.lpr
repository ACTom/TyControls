program dbcontrols_example;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, umain, LCLTranslator, SysUtils;

{ Without this the project resource -- where the XP manifest lives -- is never
  linked, so UseXPManifest in the .lpi has no effect: no common-controls v6 and
  no DPI-awareness declaration. }
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
  { The data-aware controls keep their strings (the navigator's hints and its delete
    question) in a catalogue of their own, beside the package. }
  TranslateUnitResourceStringsEx('', LangDir, 'tycontrols.db', 'tyControls.DB.StrConsts');
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
