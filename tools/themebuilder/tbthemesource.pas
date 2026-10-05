unit tbthemesource;
{ The editor's text as a theme source, so the preview loads it the way an application loads
  a theme from a folder: the text is the entry stylesheet, url() and @import resolve from the
  document's folder. An untitled document has no folder ('' ): relative paths then resolve
  to nothing, and the problem list says so. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, tyControls.ThemeBundle;

type
  { editor text as a theme source: url() and @import resolve from ABaseDir ('' = none) }
  TTbTextThemeSource = class(TInterfacedObject, ITyThemeSource)
  private
    FText, FBaseDir: string;
  public
    constructor Create(const AText, ABaseDir: string);
    function RootCss: string;
    function ReadText(const ARelPath: string; out S: string): Boolean;
    function OpenAsset(const ARelPath: string; out Stream: TStream): Boolean;
    function Manifest: TTyThemeManifest;
    function RootName: string;
    function AssetBaseDir: string;
  end;

implementation

constructor TTbTextThemeSource.Create(const AText, ABaseDir: string);
begin
  inherited Create;
  FText := AText;
  FBaseDir := ABaseDir;
  if FBaseDir <> '' then
    FBaseDir := IncludeTrailingPathDelimiter(FBaseDir);
end;

function TTbTextThemeSource.RootCss: string;
begin
  Result := FText;
end;

function TTbTextThemeSource.ReadText(const ARelPath: string; out S: string): Boolean;
var
  sl: TStringList;
begin
  S := '';
  Result := False;
  if (FBaseDir = '') or not FileExists(FBaseDir + ARelPath) then
    Exit;
  sl := TStringList.Create;
  try
    try
      sl.LoadFromFile(FBaseDir + ARelPath);
      S := sl.Text;
      Result := True;
    except
      Result := False;
    end;
  finally
    sl.Free;
  end;
end;

function TTbTextThemeSource.OpenAsset(const ARelPath: string; out Stream: TStream): Boolean;
begin
  Stream := nil;
  Result := False;
  if (FBaseDir = '') or not FileExists(FBaseDir + ARelPath) then
    Exit;
  try
    Stream := TFileStream.Create(FBaseDir + ARelPath, fmOpenRead or fmShareDenyNone);
    Result := True;
  except
    Stream := nil;
    Result := False;
  end;
end;

function TTbTextThemeSource.Manifest: TTyThemeManifest;
begin
  Result := Default(TTyThemeManifest);
  Result.Entry := 'theme.tycss';
end;

function TTbTextThemeSource.RootName: string;
begin
  Result := 'editor';
end;

function TTbTextThemeSource.AssetBaseDir: string;
begin
  Result := FBaseDir;
end;

end.
