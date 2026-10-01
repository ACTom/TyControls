unit test.themebuilder.aiclient;
{ The AI client (phase 3): one streamed call against the local server through WinHTTP --
  both formats, every failure told in one sentence, the key never in it
  (TTbAiClientTests); the AI services' profiles and keys (TTbAiSettingsTests). The client
  checks live in tbaichecks: the WSL console program runs them over libcurl too. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry;

type
  TTbAiClientTests = class(TTestCase)
  protected
    procedure SetUp; override;
  published
    procedure TestAnOpenAIStream;            { C1 }
    procedure TestAnAnthropicStream;         { C2 }
    procedure TestTheKeyIsScrubbed;          { C3 }
    procedure TestARateLimit;                { C4 }
    procedure TestNotFound;                  { C5 }
    procedure TestServerErrors;              { C6 }
    procedure TestABrokenStream;             { C7 }
    procedure TestOnlyTheServiceSaysDone;    { C8 }
    procedure TestSilenceTimesOut;           { C9 }
    procedure TestAnErrorInTheStream;        { C10 }
    procedure TestCutOff;                    { C11 }
    procedure TestDeclined;                  { C12 }
    procedure TestAReplyNotStreamed;         { C13 }
    procedure TestNotTheExpectedFormat;      { C14 }
    procedure TestStop;                      { C15 }
    procedure TestNoKeyNoHeader;             { C16 }
    procedure TestScrubbing;                 { C17 }
  end;

  TTbAiSettingsTests = class(TTestCase)
  private
    FDir: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestARoundTrip;                { K1 }
    procedure TestTheKeyIsEncrypted;         { K2 }
    procedure TestATamperedKeyIsNoKey;       { K3 }
    procedure TestDeletingTakesTheKey;       { K4 }
    procedure TestNoFileAndNoFolder;         { K5 }
    procedure TestThePresets;                { K6 }
    procedure TestTheFilesSitNextToTheSettings;   { K7 }
    procedure TestDpapiSaltsEachTime;        { K8 }
  end;

implementation

uses
  base64, tbaiformat, tbaiclient, tbaisettings, tbaichecks, test.themebuilder.sse;

const
  cTestKey = 'sk-test-ABCDEFGH12345678';

procedure TTbAiClientTests.SetUp;
begin
  TbAiFixtureDir := TbAiFixtures;
  TbCancelGraceMs := 1000;
end;

procedure TTbAiClientTests.TestAnOpenAIStream;
var
  why: string;
  ok: Boolean;
begin
  ok := AiCheckOpenAIStream(why);
  AssertTrue('C1: ' + why, ok);
end;

procedure TTbAiClientTests.TestAnAnthropicStream;
var
  why: string;
  ok: Boolean;
begin
  ok := AiCheckAnthropicStream(why);
  AssertTrue('C2: ' + why, ok);
end;

procedure TTbAiClientTests.TestTheKeyIsScrubbed;
var
  why: string;
  ok: Boolean;
begin
  ok := AiCheckKeyIsScrubbed(why);
  AssertTrue('C3: ' + why, ok);
end;

procedure TTbAiClientTests.TestARateLimit;
var
  why: string;
  ok: Boolean;
begin
  ok := AiCheckRateLimit(why);
  AssertTrue('C4: ' + why, ok);
end;

procedure TTbAiClientTests.TestNotFound;
var
  why: string;
  ok: Boolean;
begin
  ok := AiCheckNotFound(why);
  AssertTrue('C5: ' + why, ok);
end;

procedure TTbAiClientTests.TestServerErrors;
var
  why: string;
  ok: Boolean;
begin
  ok := AiCheckServerErrors(why);
  AssertTrue('C6: ' + why, ok);
end;

procedure TTbAiClientTests.TestABrokenStream;
var
  why: string;
  ok: Boolean;
begin
  ok := AiCheckBroken(why);
  AssertTrue('C7: ' + why, ok);
end;

procedure TTbAiClientTests.TestOnlyTheServiceSaysDone;
var
  why: string;
  ok: Boolean;
begin
  ok := AiCheckNeverFinished(why);
  AssertTrue('C8: ' + why, ok);
end;

procedure TTbAiClientTests.TestSilenceTimesOut;
var
  why: string;
  ok: Boolean;
begin
  ok := AiCheckTimeout(why);
  AssertTrue('C9: ' + why, ok);
end;

procedure TTbAiClientTests.TestAnErrorInTheStream;
var
  why: string;
  ok: Boolean;
begin
  ok := AiCheckStreamError(why);
  AssertTrue('C10: ' + why, ok);
end;

procedure TTbAiClientTests.TestCutOff;
var
  why: string;
  ok: Boolean;
begin
  ok := AiCheckTruncated(why);
  AssertTrue('C11: ' + why, ok);
end;

procedure TTbAiClientTests.TestDeclined;
var
  why: string;
  ok: Boolean;
begin
  ok := AiCheckRefused(why);
  AssertTrue('C12: ' + why, ok);
end;

procedure TTbAiClientTests.TestAReplyNotStreamed;
var
  why: string;
  ok: Boolean;
begin
  ok := AiCheckNotStreamed(why);
  AssertTrue('C13: ' + why, ok);
end;

procedure TTbAiClientTests.TestNotTheExpectedFormat;
var
  why: string;
  ok: Boolean;
begin
  ok := AiCheckBadFormat(why);
  AssertTrue('C14: ' + why, ok);
end;

procedure TTbAiClientTests.TestStop;
var
  why: string;
  ok: Boolean;
begin
  ok := AiCheckCancel(why);
  AssertTrue('C15: ' + why, ok);
end;

procedure TTbAiClientTests.TestNoKeyNoHeader;
var
  why: string;
  ok: Boolean;
begin
  ok := AiCheckNoKeyNoHeader(why);
  AssertTrue('C16: ' + why, ok);
end;

procedure TTbAiClientTests.TestScrubbing;
var
  s: string;
begin
  AssertEquals('C17: the whole key', 'key *** bad',
    TbScrubSecret('key sk-abcdef1234567890 bad', 'sk-abcdef1234567890'));
  s := TbScrubSecret('Incorrect API key provided: sk-proj-****ab12.', 'sk-proj-xyzxyzxyzab12');
  AssertTrue('C17: the half-masked key goes', Pos('ab12', s) = 0);
  AssertTrue('C17: the sentence stays', Pos('Incorrect API key provided:', s) = 1);
  AssertEquals('C17: a masked word without a key', 'token ***', TbScrubSecret('token ****wxyz', ''));
  AssertEquals('C17: nothing to hide', 'no secret here', TbScrubSecret('no secret here', 'k'));
  s := TbScrubSecret('the key "sk-test-ABCDEFGH12345678" was bad', 'sk-test-ABCDEFGH12345678');
  AssertTrue('C17: in quotes', Pos('ABCDEFGH', s) = 0);
end;

{ ---- TTbAiSettingsTests ---- }

procedure TTbAiSettingsTests.SetUp;
begin
  FDir := TbAiTempDir;
end;

procedure TTbAiSettingsTests.TearDown;
begin
  TbAiRemoveDir(FDir);
end;

function ReadFileBytes(const AFileName: string): RawByteString;
var
  fs: TFileStream;
begin
  Result := '';
  fs := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, fs.Size);
    if fs.Size > 0 then
      fs.ReadBuffer(Result[1], fs.Size);
  finally
    fs.Free;
  end;
end;

procedure WriteFileBytes(const AFileName: string; const AData: RawByteString);
var
  fs: TFileStream;
begin
  fs := TFileStream.Create(AFileName, fmCreate);
  try
    if AData <> '' then
      fs.WriteBuffer(AData[1], Length(AData));
  finally
    fs.Free;
  end;
end;

procedure TTbAiSettingsTests.TestARoundTrip;
var
  why: string;
  ok: Boolean;
begin
  ok := SettingsCheckRoundTrip(why);
  AssertTrue('K1: ' + why, ok);
end;

procedure TTbAiSettingsTests.TestTheKeyIsEncrypted;
var
  ini, keys: string;
  a, b: TTbAiSettings;
  p: TTbAiProfile;
  bytes: RawByteString;
begin
  TbAiFilesFor(FDir + 'themebuilder.ini', ini, keys);
  a := TTbAiSettings.Create(ini, keys);
  b := TTbAiSettings.Create(ini, keys);
  try
    p := TbPresetProfile(tapOpenAI);
    a.Put(p);
    a.SetKey(p.Id, cTestKey);
    AssertTrue('K2: saved', a.Save);
    b.Load;
    AssertTrue('K2: the key comes back', b.GetKey(p.Id) = cTestKey);
    bytes := ReadFileBytes(ini);
    AssertTrue('K2: the ini has a key entry', Pos(p.Id + '=', bytes) > 0);
    AssertTrue('K2: not the key itself', Pos(cTestKey, bytes) = 0);
    AssertTrue('K2: not part of it', Pos('ABCDEFGH', bytes) = 0);
    AssertTrue('K2: not its base64', Pos(EncodeStringBase64(cTestKey), bytes) = 0);
  finally
    a.Free;
    b.Free;
  end;
end;

procedure TTbAiSettingsTests.TestATamperedKeyIsNoKey;
var
  ini, keys: string;
  a: TTbAiSettings;
  p: TTbAiProfile;
  bytes: RawByteString;
  at, len: Integer;
begin
  TbAiFilesFor(FDir + 'themebuilder.ini', ini, keys);
  a := TTbAiSettings.Create(ini, keys);
  try
    p := TbPresetProfile(tapOpenAI);
    a.Put(p);
    a.SetKey(p.Id, cTestKey);
    AssertTrue('saved', a.Save);
  finally
    a.Free;
  end;
  bytes := ReadFileBytes(ini);
  at := Pos(p.Id + '=', bytes);
  AssertTrue('K3: the entry is there', at > 0);
  { a character in the middle of the stored value: the encrypted part, not the blob's
    fixed header (DPAPI does not check the provider id it starts with) }
  at := at + Length(p.Id) + 1;
  len := 0;
  while (at + len <= Length(bytes)) and not (bytes[at + len] in [#10, #13]) do
    Inc(len);
  at := at + len div 2;
  if bytes[at] = 'A' then bytes[at] := 'B' else bytes[at] := 'A';
  WriteFileBytes(ini, bytes);
  a := TTbAiSettings.Create(ini, keys);
  try
    a.Load;
    AssertEquals('K3: the profile is still there', 1, a.Count);
    AssertEquals('K3: a tampered key reads as none', '', a.GetKey(p.Id));
  finally
    a.Free;
  end;
end;

procedure TTbAiSettingsTests.TestDeletingTakesTheKey;
var
  ini, keys: string;
  a: TTbAiSettings;
  p, q: TTbAiProfile;
begin
  TbAiFilesFor(FDir + 'themebuilder.ini', ini, keys);
  a := TTbAiSettings.Create(ini, keys);
  try
    p := TbPresetProfile(tapOpenAI);
    q := TbPresetProfile(tapDeepSeek);
    a.Put(p);
    a.Put(q);
    a.SetKey(p.Id, cTestKey);
    AssertTrue('saved', a.Save);
    AssertTrue('the key entry is written', Pos(p.Id + '=', ReadFileBytes(ini)) > 0);
    a.Delete(p.Id);
    AssertEquals('K4: one profile left', 1, a.Count);
    AssertEquals('K4: no key in memory', '', a.GetKey(p.Id));
    AssertTrue('saved again', a.Save);
    a.Load;
    AssertEquals('K4: no key after reading back', '', a.GetKey(p.Id));
    AssertTrue('K4: no key entry in the file', Pos(p.Id + '=', ReadFileBytes(ini)) = 0);
  finally
    a.Free;
  end;
end;

procedure TTbAiSettingsTests.TestNoFileAndNoFolder;
var
  a: TTbAiSettings;
  p: TTbAiProfile;
  blocker: string;
begin
  a := TTbAiSettings.Create(FDir + 'none' + PathDelim + 'themebuilder-ai.ini', '');
  try
    a.Load;
    AssertEquals('K5: no file, no profiles', 0, a.Count);
    AssertFalse('K5: no current', a.Current(p));
  finally
    a.Free;
  end;
  blocker := FDir + 'blocker';
  WriteFileBytes(blocker, 'x');
  a := TTbAiSettings.Create(blocker + PathDelim + 'sub' + PathDelim + 'themebuilder-ai.ini', '');
  try
    a.Put(TbPresetProfile(tapCustom));
    AssertFalse('K5: a folder under a file cannot be written', a.Save);
  finally
    a.Free;
  end;
end;

procedure TTbAiSettingsTests.TestThePresets;
var
  p: TTbAiProfile;
begin
  p := TbPresetProfile(tapOpenAI);
  AssertTrue('K6: OpenAI format', p.Format = tafOpenAI);
  AssertEquals('K6: OpenAI address', 'https://api.openai.com/v1', p.BaseUrl);
  AssertEquals('K6: OpenAI model', 'gpt-5', p.Model);
  AssertEquals('K6: OpenAI sends no maximum', 0, p.MaxOutput);
  p := TbPresetProfile(tapDeepSeek);
  AssertTrue('K6: DeepSeek format', p.Format = tafOpenAI);
  AssertEquals('K6: DeepSeek address', 'https://api.deepseek.com/v1', p.BaseUrl);
  AssertEquals('K6: DeepSeek maximum', 8192, p.MaxOutput);
  p := TbPresetProfile(tapAnthropic);
  AssertTrue('K6: Anthropic format', p.Format = tafAnthropic);
  AssertEquals('K6: Anthropic address', 'https://api.anthropic.com/v1', p.BaseUrl);
  AssertEquals('K6: Anthropic model', 'claude-sonnet-5', p.Model);
  AssertTrue('K6: Anthropic needs a maximum', p.MaxOutput > 0);
  AssertEquals('K6: Anthropic maximum', TbAnthropicDefaultMaxOutput, p.MaxOutput);
  AssertEquals('K6: Anthropic waits longer', 300, p.TimeoutSec);
  p := TbPresetProfile(tapOllama);
  AssertTrue('K6: Ollama format', p.Format = tafOpenAI);
  AssertEquals('K6: Ollama address', 'http://localhost:11434/v1', p.BaseUrl);
  AssertEquals('K6: Ollama maximum', 0, p.MaxOutput);
  p := TbPresetProfile(tapCustom);
  AssertEquals('K6: custom has no address', '', p.BaseUrl);
  AssertEquals('K6: custom maximum', 0, p.MaxOutput);
  AssertTrue('K6: a fresh id each time', TbPresetProfile(tapOpenAI).Id <> TbPresetProfile(tapOpenAI).Id);
  AssertEquals('K6: twelve characters', 12, Length(p.Id));
end;

procedure TTbAiSettingsTests.TestTheFilesSitNextToTheSettings;
var
  ini, keys: string;
begin
  TbAiFilesFor('C:' + PathDelim + 'x' + PathDelim + 'themebuilder.ini', ini, keys);
  AssertEquals('K7: the ini', 'C:' + PathDelim + 'x' + PathDelim + 'themebuilder-ai.ini', ini);
  {$IFDEF MSWINDOWS}
  AssertEquals('K7: no key file on Windows', '', keys);
  {$ELSE}
  AssertEquals('K7: the key file', 'C:' + PathDelim + 'x' + PathDelim + 'themebuilder-ai.keys', keys);
  {$ENDIF}
end;

procedure TTbAiSettingsTests.TestDpapiSaltsEachTime;
{$IFDEF MSWINDOWS}
var
  c1, c2, k: string;
begin
  c1 := TbProtectKey(cTestKey);
  c2 := TbProtectKey(cTestKey);
  AssertTrue('K8: two encryptions differ', c1 <> c2);
  AssertTrue('K8: the first decrypts', TbUnprotectKey(c1, k) and (k = cTestKey));
  AssertTrue('K8: the second decrypts', TbUnprotectKey(c2, k) and (k = cTestKey));
end;
{$ELSE}
begin
  { DPAPI is Windows only: the key file's mode is checked by the WSL program (K2, K9, K10) }
end;
{$ENDIF}

initialization
  RegisterTest(TTbAiClientTests);
  RegisterTest(TTbAiSettingsTests);
end.
