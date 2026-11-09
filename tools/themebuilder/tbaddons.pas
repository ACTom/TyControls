unit tbaddons;
{ Add-on styles for the Theme Builder.

  An add-on package (a chart package, say) carries tycss of its own: tokens and typeKeys the
  core does not know. The Theme Builder is a separate program that does not link the add-on,
  so it reads that tycss from files: *.tycss in an addons folder next to the exe, any file
  named with --addon <file> on the command line, and any file the person picks from the File
  menu. Each file is registered with TyRegisterAddOnCss under its name without the extension;
  the vocabulary (TyCatalogAllTokens, TyCatalogAllTypeKeys) and every list built from it grow
  with it. Loading a name again replaces the earlier text.

  TbLoadAddOnFile and TbLoadAddOnsDir raise when a file does not load (the message names the
  file); TbLoadStartupAddOns does not: it collects the messages. A style model must be alive
  when one is loaded -- TyRegisterAddOnCss loads the text into the live models, and with none
  alive a text that does not load would be refused later, by whoever creates the next one. }
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

{ Registers the tycss in AFileName under ChangeFileExt(ExtractFileName(AFileName), ''). Raises
  when the file cannot be read or its text does not load; nothing is left registered then. }
procedure TbLoadAddOnFile(const AFileName: string);

{ Every *.tycss in ADir, in name order. A folder that is not there: nothing, quietly. Every
  file is tried; if some did not load, one exception then names each. }
procedure TbLoadAddOnsDir(const ADir: string);

{ The start-up load: AExeDir's addons folder, then each file AArgs names with --addon <file>
  (or --addon=<file>). Never raises; AErrors (may be nil) gets one line per failure. Returns
  how many files were loaded. }
function TbLoadStartupAddOns(const AExeDir: string; AArgs, AErrors: TStrings): Integer;

{ ParamStr(1..ParamCount) as a list }
procedure TbCommandLine(ADest: TStrings);

implementation

uses
  tyControls.Css.AddOns;

resourcestring
  rsTbAddOnNoFile = '--addon needs a file name after it.';

function ReadText(const AFileName: string): string;
var
  fs: TFileStream;
begin
  Result := '';
  fs := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, fs.Size);
    if Length(Result) > 0 then
      fs.ReadBuffer(Result[1], Length(Result));
  finally
    fs.Free;
  end;
  { a BOM is not tycss }
  if Copy(Result, 1, 3) = #$EF#$BB#$BF then
    Delete(Result, 1, 3);
end;

procedure TbLoadAddOnFile(const AFileName: string);
begin
  TyRegisterAddOnCss(ChangeFileExt(ExtractFileName(AFileName), ''), ReadText(AFileName));
end;

procedure LoadDir(const ADir: string; var ACount: Integer);
var
  dir: string;
  names, failed: TStringList;
  sr: TSearchRec;
  i: Integer;
begin
  if (ADir = '') or not DirectoryExists(ADir) then Exit;
  dir := IncludeTrailingPathDelimiter(ADir);
  names := TStringList.Create;
  failed := TStringList.Create;
  try
    names.Sorted := True;
    if FindFirst(dir + '*.tycss', faAnyFile and not faDirectory, sr) = 0 then
    try
      repeat
        names.Add(sr.Name);
      until FindNext(sr) <> 0;
    finally
      FindClose(sr);
    end;
    for i := 0 to names.Count - 1 do
      try
        TbLoadAddOnFile(dir + names[i]);
        Inc(ACount);
      except
        on E: Exception do
          failed.Add(dir + names[i] + ': ' + E.Message);
      end;
    if failed.Count > 0 then
      raise Exception.Create(Trim(failed.Text));
  finally
    failed.Free;
    names.Free;
  end;
end;

procedure TbLoadAddOnsDir(const ADir: string);
var
  n: Integer;
begin
  n := 0;
  LoadDir(ADir, n);
end;

function TbLoadStartupAddOns(const AExeDir: string; AArgs, AErrors: TStrings): Integer;
var
  i: Integer;
  a, f: string;

  procedure Fail(const AMsg: string);
  begin
    if AErrors <> nil then
      AErrors.Add(AMsg);
  end;

  procedure TryFile(const AFileName: string);
  begin
    try
      TbLoadAddOnFile(AFileName);
      Inc(Result);
    except
      on E: Exception do
        Fail(AFileName + ': ' + E.Message);
    end;
  end;

begin
  Result := 0;
  if AExeDir <> '' then
  begin
    try
      LoadDir(IncludeTrailingPathDelimiter(AExeDir) + 'addons', Result);
    except
      on E: Exception do
        Fail(E.Message);
    end;
  end;
  if AArgs = nil then Exit;
  i := 0;
  while i < AArgs.Count do
  begin
    a := AArgs[i];
    f := '';
    if a = '--addon' then
    begin
      Inc(i);
      if i < AArgs.Count then
        f := AArgs[i]
      else
        Fail(rsTbAddOnNoFile);
    end
    else if Copy(a, 1, 8) = '--addon=' then
      f := Copy(a, 9, MaxInt);
    if f <> '' then
      TryFile(f);
    Inc(i);
  end;
end;

procedure TbCommandLine(ADest: TStrings);
var
  i: Integer;
begin
  for i := 1 to ParamCount do
    ADest.Add(ParamStr(i));
end;

end.
