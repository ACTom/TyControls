unit tbsettings;
{ The tool's own settings: the editor's appearance (its theme and light / dark), the
  preview's switches, and the recent files. An .ini in the user's configuration folder
  (GetAppConfigDir); the tests point it somewhere else. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils;

const
  TbMaxRecent = 10;

type
  TTbSettings = class
  private
    FFileName: string;
    FRecent: TStringList;
    FEditorTheme: string;
    FEditorDark: Boolean;
    FPreviewDark: Boolean;
    FPreviewModern: Boolean;
    function SameFile(const A, B: string): Boolean;
  public
    constructor Create(const AIniFile: string);
    destructor Destroy; override;
    procedure Load;                    { a missing file = defaults }
    procedure Save;                    { creates the directory }
    procedure AddRecent(const AFileName: string);    { to the front; no duplicates; at most TbMaxRecent }
    procedure RemoveRecent(const AFileName: string);
    property Recent: TStringList read FRecent;
    property EditorTheme: string read FEditorTheme write FEditorTheme;   { default 'default' }
    property EditorDark: Boolean read FEditorDark write FEditorDark;
    property PreviewDark: Boolean read FPreviewDark write FPreviewDark;
    property PreviewModern: Boolean read FPreviewModern write FPreviewModern;
    property FileName: string read FFileName;
  end;

{ GetAppConfigDir(False) + 'themebuilder.ini' }
function TbDefaultSettingsFile: string;

implementation

uses
  IniFiles;

function TbDefaultSettingsFile: string;
begin
  Result := IncludeTrailingPathDelimiter(GetAppConfigDir(False)) + 'themebuilder.ini';
end;

constructor TTbSettings.Create(const AIniFile: string);
begin
  inherited Create;
  FFileName := AIniFile;
  FRecent := TStringList.Create;
  FEditorTheme := 'default';
end;

destructor TTbSettings.Destroy;
begin
  FRecent.Free;
  inherited Destroy;
end;

function TTbSettings.SameFile(const A, B: string): Boolean;
begin
  {$IFDEF MSWINDOWS}
  Result := SameText(A, B);
  {$ELSE}
  Result := A = B;
  {$ENDIF}
end;

procedure TTbSettings.Load;
var
  ini: TIniFile;
  i: Integer;
  f: string;
begin
  FEditorTheme := 'default';
  FEditorDark := False;
  FPreviewDark := False;
  FPreviewModern := False;
  FRecent.Clear;
  if (FFileName = '') or not FileExists(FFileName) then Exit;
  ini := TIniFile.Create(FFileName);
  try
    FEditorTheme := ini.ReadString('Editor', 'Theme', 'default');
    if FEditorTheme = '' then
      FEditorTheme := 'default';
    FEditorDark := ini.ReadBool('Editor', 'Dark', False);
    FPreviewDark := ini.ReadBool('Preview', 'Dark', False);
    FPreviewModern := ini.ReadBool('Preview', 'Modern', False);
    for i := 0 to TbMaxRecent - 1 do
    begin
      f := ini.ReadString('Recent', 'File' + IntToStr(i), '');
      if f <> '' then
        FRecent.Add(f);
    end;
  finally
    ini.Free;
  end;
end;

procedure TTbSettings.Save;
var
  ini: TIniFile;
  i: Integer;
begin
  if FFileName = '' then Exit;
  ForceDirectories(ExtractFileDir(FFileName));
  ini := TIniFile.Create(FFileName);
  try
    ini.WriteString('Editor', 'Theme', FEditorTheme);
    ini.WriteBool('Editor', 'Dark', FEditorDark);
    ini.WriteBool('Preview', 'Dark', FPreviewDark);
    ini.WriteBool('Preview', 'Modern', FPreviewModern);
    ini.EraseSection('Recent');
    for i := 0 to FRecent.Count - 1 do
      ini.WriteString('Recent', 'File' + IntToStr(i), FRecent[i]);
    ini.UpdateFile;
  finally
    ini.Free;
  end;
end;

procedure TTbSettings.AddRecent(const AFileName: string);
begin
  if AFileName = '' then Exit;
  RemoveRecent(AFileName);
  FRecent.Insert(0, AFileName);
  while FRecent.Count > TbMaxRecent do
    FRecent.Delete(FRecent.Count - 1);
end;

procedure TTbSettings.RemoveRecent(const AFileName: string);
var
  i: Integer;
begin
  for i := FRecent.Count - 1 downto 0 do
    if SameFile(FRecent[i], AFileName) then
      FRecent.Delete(i);
end;

end.
