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

implementation

uses
  tbaiclient, tbaichecks, test.themebuilder.sse;

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

initialization
  RegisterTest(TTbAiClientTests);
end.
