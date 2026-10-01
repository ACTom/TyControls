unit tbaisettings;
{ The AI services the user has set up ("profiles", one of them current) and their keys.

  Next to the tool's own settings file (TbAiFilesFor): themebuilder-ai.ini --

    [General]  Current=<id>  Order=<id>,<id>,...
    [Profile.<id>]  Name, Format (openai / anthropic), BaseUrl, Model, MaxOutput, TimeoutSec
    [Keys]  <id>=<the key encrypted with DPAPI, base64>          (Windows only)

  Keys (spec §7.1): on Windows encrypted for the current user (CryptProtectData, an entropy
  of our own, no UI) and kept in the ini as base64 of the cipher text; elsewhere in a file of
  their own, themebuilder-ai.keys, "<id>=<key>" per line, readable by the user only (0600 from
  the moment it is created -- written to a temporary file opened with that mode, then
  renamed over; a key file found readable by others is set back to 0600 when it is read).
  A key never goes into the ini on Linux / macOS, nor into any message.

  Saving is best effort, as for the tool's settings: False when a file could not be written,
  never an exception (closing the window must not hang on it). Every file goes to a
  temporary one first and replaces the old in one step.

  No LCL: the WSL console program compiles it too. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, IniFiles, base64, tbaiformat;

resourcestring
  rsTbAiPresetLocal = 'Local (Ollama)';
  rsTbAiPresetCustom = 'Custom';

type
  TTbAiPreset = (tapOpenAI, tapDeepSeek, tapAnthropic, tapOllama, tapCustom);

  TTbAiSettings = class
  private
    FIniFile, FKeyFile: string;
    FProfiles: array of TTbAiProfile;
    FKeys: TStringList;           { id=key }
    FCurrentId: string;
    procedure LoadKeys(AIni: TMemIniFile);
  public
    constructor Create(const AIniFile, AKeyFile: string);
    destructor Destroy; override;
    procedure Load;                               { a missing file = no profiles }
    function Save: Boolean;                       { best effort; False when it could not write }
    function Count: Integer;
    function Profile(AIndex: Integer): TTbAiProfile;
    function IndexOfId(const AId: string): Integer;
    procedure Put(const AProfile: TTbAiProfile);  { add, or replace the one with that Id }
    procedure Delete(const AId: string);          { and its key }
    function GetKey(const AId: string): string;   { '' when none or unreadable }
    procedure SetKey(const AId, AKey: string);    { '' removes; written by Save }
    function Current(out AProfile: TTbAiProfile): Boolean;
    property CurrentId: string read FCurrentId write FCurrentId;
    property IniFile: string read FIniFile;
    property KeyFile: string read FKeyFile;
  end;

function TbPresetProfile(APreset: TTbAiPreset): TTbAiProfile;   { a fresh Id each call }
function TbPresetCaption(APreset: TTbAiPreset): string;
function TbNewProfileId: string;
procedure TbAiFilesFor(const ASettingsIni: string; out AIniFile, AKeyFile: string);
{$IFDEF MSWINDOWS}
function TbProtectKey(const AKey: string): string;               { DPAPI, base64 }
function TbUnprotectKey(const AStored: string; out AKey: string): Boolean;
{$ENDIF}
{ a file only its owner can read (0600 from the start); on Windows a plain file }
function TbWritePrivateFile(const AFileName: string; const AData: RawByteString): Boolean;

implementation

uses
  {$IFDEF MSWINDOWS} Windows {$ELSE} BaseUnix, ctypes {$ENDIF};

const
  cGeneral = 'General';
  cKeys = 'Keys';
  cProfilePrefix = 'Profile.';

{$IFDEF MSWINDOWS}
type
  TDataBlob = record
    cbData: DWORD;
    pbData: PByte;
  end;
  PDataBlob = ^TDataBlob;

const
  CRYPTPROTECT_UI_FORBIDDEN = 1;
  cEntropy: RawByteString = 'TyControls.ThemeBuilder.AI';
  MOVEFILE_REPLACE_EXISTING = 1;
  MOVEFILE_WRITE_THROUGH = 8;

function CryptProtectData(pDataIn: PDataBlob; szDataDescr: PWideChar; pOptionalEntropy: PDataBlob;
  pvReserved, pPromptStruct: Pointer; dwFlags: DWORD; pDataOut: PDataBlob): BOOL;
  stdcall; external 'crypt32.dll';
function CryptUnprotectData(pDataIn: PDataBlob; ppszDataDescr: PPWideChar; pOptionalEntropy: PDataBlob;
  pvReserved, pPromptStruct: Pointer; dwFlags: DWORD; pDataOut: PDataBlob): BOOL;
  stdcall; external 'crypt32.dll';

function TbProtectKey(const AKey: string): string;
var
  data: RawByteString;
  inBlob, entropy, outBlob: TDataBlob;
  cipher: RawByteString;
begin
  data := AKey;                    { the key's bytes as typed (UTF-8) }
  if data = '' then
    Exit('');
  inBlob.cbData := Length(data);
  inBlob.pbData := PByte(PAnsiChar(data));
  entropy.cbData := Length(cEntropy);
  entropy.pbData := PByte(PAnsiChar(cEntropy));
  outBlob := Default(TDataBlob);
  if not CryptProtectData(@inBlob, nil, @entropy, nil, nil, CRYPTPROTECT_UI_FORBIDDEN, @outBlob) then
    raise Exception.CreateFmt('The key could not be encrypted (error %d).', [GetLastError]);
  try
    SetString(cipher, PAnsiChar(outBlob.pbData), outBlob.cbData);
  finally
    LocalFree(HLOCAL(outBlob.pbData));
  end;
  Result := EncodeStringBase64(cipher);
end;

function TbUnprotectKey(const AStored: string; out AKey: string): Boolean;
var
  cipher, plain: RawByteString;
  inBlob, entropy, outBlob: TDataBlob;
begin
  AKey := '';
  Result := False;
  try
    cipher := DecodeStringBase64(AStored);
  except
    Exit;
  end;
  if cipher = '' then Exit;
  inBlob.cbData := Length(cipher);
  inBlob.pbData := PByte(PAnsiChar(cipher));
  entropy.cbData := Length(cEntropy);
  entropy.pbData := PByte(PAnsiChar(cEntropy));
  outBlob := Default(TDataBlob);
  if not CryptUnprotectData(@inBlob, nil, @entropy, nil, nil, CRYPTPROTECT_UI_FORBIDDEN, @outBlob) then
    Exit;
  try
    SetString(plain, PAnsiChar(outBlob.pbData), outBlob.cbData);
  finally
    LocalFree(HLOCAL(outBlob.pbData));
  end;
  AKey := plain;
  Result := True;
end;

function ReplaceFile(const ATemp, ATarget: string): Boolean;
begin
  Result := MoveFileExW(PWideChar(UnicodeString(ATemp)), PWideChar(UnicodeString(ATarget)),
    MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH);
end;
{$ELSE}
function ReplaceFile(const ATemp, ATarget: string): Boolean;
begin
  Result := fpRename(PChar(ATemp), PChar(ATarget)) = 0;
end;
{$ENDIF}

function WriteBytes(const AFileName: string; const AData: RawByteString): Boolean;
var
  fs: TFileStream;
begin
  Result := False;
  try
    fs := TFileStream.Create(AFileName, fmCreate);
    try
      if AData <> '' then
        fs.WriteBuffer(AData[1], Length(AData));
    finally
      fs.Free;
    end;
    Result := True;
  except
    Result := False;
  end;
end;

{ temporary file, then one step over the old one }
function WriteReplacing(const AFileName: string; const AData: RawByteString): Boolean;
var
  tmp: string;
begin
  tmp := AFileName + '.tmp';
  Result := WriteBytes(tmp, AData) and ReplaceFile(tmp, AFileName);
  if not Result then
    SysUtils.DeleteFile(tmp);
end;

function TbWritePrivateFile(const AFileName: string; const AData: RawByteString): Boolean;
{$IFDEF MSWINDOWS}
begin
  Result := WriteReplacing(AFileName, AData);
end;
{$ELSE}
var
  tmp: string;
  fd: cint;
  done, n: Integer;
begin
  Result := False;
  tmp := AFileName + '.tmp';
  { created 0600: never readable by others, not even for a moment }
  fd := fpOpen(PChar(tmp), O_WRONLY or O_CREAT or O_TRUNC, &600);
  if fd < 0 then Exit;
  try
    { a temporary file left over with a wider mode keeps its mode under O_CREAT }
    fpChmod(PChar(tmp), &600);
    done := 0;
    while done < Length(AData) do
    begin
      n := fpWrite(fd, AData[done + 1], Length(AData) - done);
      if n <= 0 then
        Exit;
      Inc(done, n);
    end;
  finally
    fpClose(fd);
    if done < Length(AData) then
      fpUnlink(PChar(tmp));
  end;
  Result := ReplaceFile(tmp, AFileName);
  if not Result then
    fpUnlink(PChar(tmp));
end;
{$ENDIF}

function TbNewProfileId: string;
var
  g: TGUID;
  s: string;
  i: Integer;
begin
  CreateGUID(g);
  s := GUIDToString(g);
  Result := '';
  for i := 1 to Length(s) do
    if s[i] in ['0'..'9', 'A'..'F', 'a'..'f'] then
      Result := Result + LowerCase(s[i]);
  Result := Copy(Result, 1, 12);
end;

function TbPresetCaption(APreset: TTbAiPreset): string;
begin
  case APreset of
    tapOpenAI: Result := 'OpenAI';               { brand names: not translated }
    tapDeepSeek: Result := 'DeepSeek';
    tapAnthropic: Result := 'Anthropic';
    tapOllama: Result := rsTbAiPresetLocal;
  else
    Result := rsTbAiPresetCustom;
  end;
end;

function TbPresetProfile(APreset: TTbAiPreset): TTbAiProfile;
begin
  Result := Default(TTbAiProfile);
  Result.Id := TbNewProfileId;
  Result.Name := TbPresetCaption(APreset);
  Result.Format := tafOpenAI;
  Result.TimeoutSec := 120;
  case APreset of
    tapOpenAI:
      begin
        Result.BaseUrl := 'https://api.openai.com/v1';
        Result.Model := 'gpt-5';
        Result.MaxOutput := 0;      { the newer models refuse max_tokens: not sent }
      end;
    tapDeepSeek:
      begin
        Result.BaseUrl := 'https://api.deepseek.com/v1';
        Result.Model := 'deepseek-chat';
        Result.MaxOutput := 8192;   { deepseek-chat's limit }
      end;
    tapAnthropic:
      begin
        Result.Format := tafAnthropic;
        Result.BaseUrl := 'https://api.anthropic.com/v1';
        Result.Model := 'claude-sonnet-5';
        Result.MaxOutput := TbAnthropicDefaultMaxOutput;
        Result.TimeoutSec := 300;
      end;
    tapOllama:
      begin
        Result.BaseUrl := 'http://localhost:11434/v1';
        Result.Model := 'qwen2.5-coder:7b';
        Result.MaxOutput := 0;
        Result.TimeoutSec := 300;   { a local model on a CPU is slow to start }
      end;
  end;
end;

procedure TbAiFilesFor(const ASettingsIni: string; out AIniFile, AKeyFile: string);
var
  dir: string;
begin
  dir := ExtractFilePath(ASettingsIni);
  AIniFile := dir + 'themebuilder-ai.ini';
  {$IFDEF MSWINDOWS}
  AKeyFile := '';
  {$ELSE}
  AKeyFile := dir + 'themebuilder-ai.keys';
  {$ENDIF}
end;

function FormatName(AFormat: TTbAiFormat): string;
begin
  if AFormat = tafAnthropic then Result := 'anthropic' else Result := 'openai';
end;

{ ---- TTbAiSettings ---- }

constructor TTbAiSettings.Create(const AIniFile, AKeyFile: string);
begin
  inherited Create;
  FIniFile := AIniFile;
  FKeyFile := AKeyFile;
  FKeys := TStringList.Create;
end;

destructor TTbAiSettings.Destroy;
begin
  FKeys.Free;
  inherited Destroy;
end;

function TTbAiSettings.Count: Integer;
begin
  Result := Length(FProfiles);
end;

function TTbAiSettings.Profile(AIndex: Integer): TTbAiProfile;
begin
  Result := FProfiles[AIndex];
end;

function TTbAiSettings.IndexOfId(const AId: string): Integer;
var
  i: Integer;
begin
  for i := 0 to High(FProfiles) do
    if FProfiles[i].Id = AId then
      Exit(i);
  Result := -1;
end;

procedure TTbAiSettings.Put(const AProfile: TTbAiProfile);
var
  i: Integer;
begin
  i := IndexOfId(AProfile.Id);
  if i < 0 then
  begin
    i := Length(FProfiles);
    SetLength(FProfiles, i + 1);
  end;
  FProfiles[i] := AProfile;
end;

procedure TTbAiSettings.Delete(const AId: string);
var
  i, k: Integer;
begin
  i := IndexOfId(AId);
  if i >= 0 then
  begin
    for k := i to High(FProfiles) - 1 do
      FProfiles[k] := FProfiles[k + 1];
    SetLength(FProfiles, Length(FProfiles) - 1);
  end;
  k := FKeys.IndexOfName(AId);
  if k >= 0 then
    FKeys.Delete(k);
  if FCurrentId = AId then
    FCurrentId := '';
end;

function TTbAiSettings.GetKey(const AId: string): string;
var
  k: Integer;
begin
  k := FKeys.IndexOfName(AId);
  if k < 0 then
    Result := ''
  else
    Result := FKeys.ValueFromIndex[k];
end;

procedure TTbAiSettings.SetKey(const AId, AKey: string);
var
  i, k: Integer;
begin
  for i := 1 to Length(AKey) do
    if AKey[i] < ' ' then
      raise EArgumentException.Create('A key cannot hold line breaks or control characters.');
  k := FKeys.IndexOfName(AId);
  if AKey = '' then
  begin
    if k >= 0 then
      FKeys.Delete(k);
  end
  else if k >= 0 then
    FKeys[k] := AId + '=' + AKey
  else
    FKeys.Add(AId + '=' + AKey);
end;

function TTbAiSettings.Current(out AProfile: TTbAiProfile): Boolean;
var
  i: Integer;
begin
  AProfile := Default(TTbAiProfile);
  Result := Length(FProfiles) > 0;
  if not Result then Exit;
  i := IndexOfId(FCurrentId);
  if i < 0 then
    i := 0;
  AProfile := FProfiles[i];
end;

procedure TTbAiSettings.LoadKeys(AIni: TMemIniFile);
var
  names, lines: TStringList;
  i, p: Integer;
  key, id: string;
  {$IFNDEF MSWINDOWS}
  st: TStat;
  {$ENDIF}
begin
  FKeys.Clear;
  {$IFDEF MSWINDOWS}
  names := TStringList.Create;
  try
    AIni.ReadSection(cKeys, names);
    for i := 0 to names.Count - 1 do
      if TbUnprotectKey(AIni.ReadString(cKeys, names[i], ''), key) and (key <> '') then
        FKeys.Add(names[i] + '=' + key);
  finally
    names.Free;
  end;
  lines := nil;
  p := 0;
  id := '';
  {$ELSE}
  names := nil;
  if (FKeyFile = '') or not FileExists(FKeyFile) then Exit;
  { a key file others can read is set back to the owner alone }
  if (fpStat(PChar(FKeyFile), st) = 0) and ((st.st_mode and &077) <> 0) then
    fpChmod(PChar(FKeyFile), &600);
  lines := TStringList.Create;
  try
    try
      lines.LoadFromFile(FKeyFile);
    except
      Exit;
    end;
    for i := 0 to lines.Count - 1 do
    begin
      p := Pos('=', lines[i]);
      if p <= 1 then Continue;
      id := Copy(lines[i], 1, p - 1);
      key := Copy(lines[i], p + 1, MaxInt);
      if key <> '' then
        FKeys.Add(id + '=' + key);
    end;
  finally
    lines.Free;
  end;
  {$ENDIF}
end;

procedure TTbAiSettings.Load;
var
  ini: TMemIniFile;
  order: TStringList;
  i: Integer;
  sec: string;
  pr: TTbAiProfile;
begin
  FProfiles := nil;
  FKeys.Clear;
  FCurrentId := '';
  if (FIniFile = '') or not FileExists(FIniFile) then
  begin
    {$IFNDEF MSWINDOWS}
    { no ini: no profiles, and no key belongs to anything }
    {$ENDIF}
    Exit;
  end;
  try
    ini := TMemIniFile.Create(FIniFile);
  except
    Exit;
  end;
  order := TStringList.Create;
  try
    order.Delimiter := ',';
    order.StrictDelimiter := True;
    order.DelimitedText := ini.ReadString(cGeneral, 'Order', '');
    for i := 0 to order.Count - 1 do
    begin
      sec := cProfilePrefix + Trim(order[i]);
      if (Trim(order[i]) = '') or not ini.SectionExists(sec) then
        Continue;
      pr := Default(TTbAiProfile);
      pr.Id := Trim(order[i]);
      pr.Name := ini.ReadString(sec, 'Name', pr.Id);
      if SameText(ini.ReadString(sec, 'Format', 'openai'), 'anthropic') then
        pr.Format := tafAnthropic
      else
        pr.Format := tafOpenAI;
      pr.BaseUrl := ini.ReadString(sec, 'BaseUrl', '');
      pr.Model := ini.ReadString(sec, 'Model', '');
      pr.MaxOutput := ini.ReadInteger(sec, 'MaxOutput', 0);
      pr.TimeoutSec := ini.ReadInteger(sec, 'TimeoutSec', 120);
      if IndexOfId(pr.Id) < 0 then
        Put(pr);
    end;
    FCurrentId := ini.ReadString(cGeneral, 'Current', '');
    if (IndexOfId(FCurrentId) < 0) and (Length(FProfiles) > 0) then
      FCurrentId := FProfiles[0].Id;
    LoadKeys(ini);
  finally
    order.Free;
    ini.Free;
  end;
end;

function TTbAiSettings.Save: Boolean;
var
  ini: TMemIniFile;
  lines: TStringList;
  i: Integer;
  ids, sec, keyText: string;
  pr: TTbAiProfile;
begin
  Result := False;
  if FIniFile = '' then Exit;
  try
    if not ForceDirectories(ExtractFileDir(FIniFile)) then Exit;
    ini := TMemIniFile.Create('');
    lines := TStringList.Create;
    try
      ids := '';
      for i := 0 to High(FProfiles) do
      begin
        pr := FProfiles[i];
        if ids <> '' then ids := ids + ',';
        ids := ids + pr.Id;
        sec := cProfilePrefix + pr.Id;
        ini.WriteString(sec, 'Name', pr.Name);
        ini.WriteString(sec, 'Format', FormatName(pr.Format));
        ini.WriteString(sec, 'BaseUrl', pr.BaseUrl);
        ini.WriteString(sec, 'Model', pr.Model);
        ini.WriteInteger(sec, 'MaxOutput', pr.MaxOutput);
        ini.WriteInteger(sec, 'TimeoutSec', pr.TimeoutSec);
      end;
      ini.WriteString(cGeneral, 'Current', FCurrentId);
      ini.WriteString(cGeneral, 'Order', ids);
      {$IFDEF MSWINDOWS}
      for i := 0 to FKeys.Count - 1 do
        if IndexOfId(FKeys.Names[i]) >= 0 then
          ini.WriteString(cKeys, FKeys.Names[i], TbProtectKey(FKeys.ValueFromIndex[i]));
      {$ENDIF}
      ini.GetStrings(lines);
      if not WriteReplacing(FIniFile, lines.Text) then Exit;
      {$IFNDEF MSWINDOWS}
      if FKeyFile <> '' then
      begin
        keyText := '';
        for i := 0 to FKeys.Count - 1 do
          if IndexOfId(FKeys.Names[i]) >= 0 then
            keyText := keyText + FKeys.Names[i] + '=' + FKeys.ValueFromIndex[i] + #10;
        if not TbWritePrivateFile(FKeyFile, keyText) then Exit;
      end;
      {$ENDIF}
      keyText := '';
    finally
      lines.Free;
      ini.Free;
    end;
    Result := True;
  except
    Result := False;      { a full disk, a folder that cannot be made: the tool goes on }
  end;
end;

end.
