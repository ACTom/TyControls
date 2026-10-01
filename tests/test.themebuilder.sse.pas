unit test.themebuilder.sse;
{ The AI page's stream reading (phase 3): the server-sent events reader, fed every way a
  network might cut the bytes (TTbSseTests), and the two request formats with their
  streamed replies, read from hand-written samples (TTbAiFormatTests). }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, tbsse, tbaiformat;

type
  TTbSseTests = class(TTestCase)
  private
    procedure Expect(const AName: string; const AInput: RawByteString; const AWant: string;
      AWantDropped: Boolean = False);
  published
    procedure TestTwoEvents;                 { E1 }
    procedure TestDataLinesJoin;             { E2 }
    procedure TestCrLfBreaks;                { E3 }
    procedure TestCrBreaks;                  { E4 }
    procedure TestACommentIsNoData;          { E5 }
    procedure TestOneSpaceGoes;              { E6 }
    procedure TestAnEmptyDataLineCounts;     { E7 }
    procedure TestNoDataNoEvent;             { E8 }
    procedure TestTheBomAtTheStartOnly;      { E9 }
    procedure TestOtherFieldsAreIgnored;     { E10 }
    procedure TestAHalfEventIsDropped;       { E11 }
    procedure TestUtf8SplitAnywhere;         { E12 }
    procedure TestTheSamples;                { E13 }
    { after the phase 3 reviews }
    procedure TestALineHasALimit;            { E14 }
    procedure TestAnEventHasALimit;          { E15 }
  end;

  TTbAiFormatTests = class(TTestCase)
  published
    procedure TestTheEndpoint;               { A1 }
    procedure TestTheHeaders;                { A2 }
    procedure TestTheBody;                   { A3 }
    procedure TestAnOpenAIStream;            { A4 }
    procedure TestReasoningIsThinking;       { A5 }
    procedure TestEscapedCharacters;         { A6 }
    procedure TestOpenAICutOffAndError;      { A7 }
    procedure TestAnAnthropicStream;         { A8 }
    procedure TestAnthropicEnds;             { A9 }
    procedure TestErrorBodies;               { A10 }
    procedure TestAWholeReply;               { A11 }
    procedure TestNotJsonIsAnError;          { A12 }
  end;

{ the samples' folder, with a trailing delimiter }
function TbAiFixtures: string;
function TbReadFixture(const AName: string): RawByteString;

implementation

uses
  fpjson, jsonparser, test.themebuilder.golden;

const
  cChinese = #$E4#$B8#$AD#$E6#$96#$87;       { 中文 }
  cPalette = #$F0#$9F#$8E#$A8;               { U+1F3A8 }

type
  TSseLog = class
  public
    Text: string;
    procedure OnEvent(const AEvent: TTbSseEvent);
  end;

  TDeltaLog = class
  public
    Format: TTbAiFormat;
    Kinds: array of TTbStreamPiece;
    Ends: array of TTbStreamPiece;
    Texts: TStringList;
    Names: TStringList;
    constructor Create(AFormat: TTbAiFormat);
    destructor Destroy; override;
    procedure OnEvent(const AEvent: TTbSseEvent);
    function JoinedText: string;
    function Count(AKind: TTbStreamPiece): Integer;
    function Has(AKind: TTbStreamPiece): Boolean;
    function LastMeaningful: TTbStreamPiece;
  end;

function TbAiFixtures: string;
begin
  Result := TbRepoDir + 'tests' + PathDelim + 'fixtures' + PathDelim + 'themebuilder' + PathDelim +
    'ai' + PathDelim;
end;

function TbReadFixture(const AName: string): RawByteString;
var
  fs: TFileStream;
begin
  Result := '';
  fs := TFileStream.Create(TbAiFixtures + AName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, fs.Size);
    if fs.Size > 0 then
      fs.ReadBuffer(Result[1], fs.Size);
  finally
    fs.Free;
  end;
end;

procedure TSseLog.OnEvent(const AEvent: TTbSseEvent);
begin
  Text := Text + AEvent.Name + '=' + AEvent.Data + #1;
end;

constructor TDeltaLog.Create(AFormat: TTbAiFormat);
begin
  inherited Create;
  Format := AFormat;
  Texts := TStringList.Create;
  Names := TStringList.Create;
end;

destructor TDeltaLog.Destroy;
begin
  Texts.Free;
  Names.Free;
  inherited Destroy;
end;

procedure TDeltaLog.OnEvent(const AEvent: TTbSseEvent);
var
  d: TTbStreamDelta;
  n: Integer;
begin
  d := TbParseStreamEvent(Format, AEvent);
  n := Length(Kinds);
  SetLength(Kinds, n + 1);
  SetLength(Ends, n + 1);
  Kinds[n] := d.Kind;
  Ends[n] := d.Ends;
  Texts.Add(d.Text);
  Names.Add(AEvent.Name);
end;

function TDeltaLog.JoinedText: string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(Kinds) do
    if Kinds[i] = tspText then
      Result := Result + Texts[i];
end;

function TDeltaLog.Count(AKind: TTbStreamPiece): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(Kinds) do
    if Kinds[i] = AKind then
      Inc(Result);
end;

function TDeltaLog.Has(AKind: TTbStreamPiece): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to High(Kinds) do
    if (Kinds[i] = AKind) or (Ends[i] = AKind) then
      Exit(True);
end;

function TDeltaLog.LastMeaningful: TTbStreamPiece;
var
  i: Integer;
begin
  Result := tspNone;
  for i := 0 to High(Kinds) do
    if Kinds[i] <> tspNone then
      Result := Kinds[i];
end;

{ the events of AFile, through the reader in one piece }
function ReadSample(const AFile: string; AFormat: TTbAiFormat): TDeltaLog;
var
  p: TTbSseParser;
begin
  Result := TDeltaLog.Create(AFormat);
  p := TTbSseParser.Create(@Result.OnEvent);
  try
    p.Feed(TbReadFixture(AFile));
    p.Finish;
  finally
    p.Free;
  end;
end;

{ ---- TTbSseTests ---- }

type
  TFeedMode = (fmWhole, fmBytes, fmSplit);

function RunSse(const AInput: RawByteString; AMode: TFeedMode; ASplit: Integer;
  out ADropped: Boolean; out ACount: Integer): string;
var
  log: TSseLog;
  p: TTbSseParser;
  i: Integer;
begin
  log := TSseLog.Create;
  p := TTbSseParser.Create(@log.OnEvent);
  try
    case AMode of
      fmWhole:
        p.Feed(AInput);
      fmBytes:
        for i := 1 to Length(AInput) do
          p.Feed(AInput[i]);
      fmSplit:
        begin
          p.Feed(Copy(AInput, 1, ASplit));
          p.Feed(Copy(AInput, ASplit + 1, MaxInt));
        end;
    end;
    p.Finish;
    ADropped := p.DroppedPartial;
    ACount := p.EventCount;
    Result := log.Text;
  finally
    p.Free;
    log.Free;
  end;
end;

procedure TTbSseTests.Expect(const AName: string; const AInput: RawByteString;
  const AWant: string; AWantDropped: Boolean);
var
  got: string;
  dropped: Boolean;
  count, k: Integer;
begin
  got := RunSse(AInput, fmWhole, 0, dropped, count);
  AssertEquals(AName + ': in one piece', AWant, got);
  AssertEquals(AName + ': dropped, in one piece', AWantDropped, dropped);
  got := RunSse(AInput, fmBytes, 0, dropped, count);
  AssertEquals(AName + ': byte by byte', AWant, got);
  AssertEquals(AName + ': dropped, byte by byte', AWantDropped, dropped);
  for k := 1 to Length(AInput) - 1 do
  begin
    got := RunSse(AInput, fmSplit, k, dropped, count);
    AssertEquals(AName + ': cut after byte ' + IntToStr(k), AWant, got);
    AssertEquals(AName + ': dropped, cut after byte ' + IntToStr(k), AWantDropped, dropped);
  end;
end;

procedure TTbSseTests.TestTwoEvents;
begin
  Expect('E1', 'data: a'#10#10'data: b'#10#10, 'message=a'#1'message=b'#1);
end;

procedure TTbSseTests.TestDataLinesJoin;
begin
  Expect('E2', 'event: x'#10'data: 1'#10'data: 2'#10#10, 'x=1'#10'2'#1);
end;

procedure TTbSseTests.TestCrLfBreaks;
begin
  Expect('E3', 'event: x'#13#10'data: 1'#13#10'data: 2'#13#10#13#10, 'x=1'#10'2'#1);
end;

procedure TTbSseTests.TestCrBreaks;
begin
  Expect('E4', 'event: x'#13'data: 1'#13'data: 2'#13#13, 'x=1'#10'2'#1);
end;

procedure TTbSseTests.TestACommentIsNoData;
begin
  Expect('E5', ': keep-alive'#10#10'data: x'#10#10, 'message=x'#1);
end;

procedure TTbSseTests.TestOneSpaceGoes;
begin
  Expect('E6', 'data:x'#10'data:  y'#10#10, 'message=x'#10' y'#1);
end;

procedure TTbSseTests.TestAnEmptyDataLineCounts;
begin
  Expect('E7', 'data'#10#10, 'message='#1);
end;

procedure TTbSseTests.TestNoDataNoEvent;
begin
  Expect('E8', 'event: e'#10#10, '');
  Expect('E8', 'event: e'#10#10'data: x'#10#10, 'message=x'#1);
end;

procedure TTbSseTests.TestTheBomAtTheStartOnly;
begin
  Expect('E9', #$EF#$BB#$BF'data: a'#10#10, 'message=a'#1);
  Expect('E9', 'data: a'#10#10#$EF#$BB#$BF'data: b'#10#10, 'message=a'#1);
end;

procedure TTbSseTests.TestOtherFieldsAreIgnored;
begin
  Expect('E10', 'id: 7'#10'retry: 10'#10'data: z'#10#10, 'message=z'#1);
end;

procedure TTbSseTests.TestAHalfEventIsDropped;
begin
  Expect('E11', 'data: half', '', True);
end;

procedure TTbSseTests.TestUtf8SplitAnywhere;
begin
  Expect('E12', 'data: ' + cChinese + #10#10, 'message=' + cChinese + #1);
end;

procedure TTbSseTests.TestTheSamples;

  procedure One(const AFile: string; AEvents: Integer);
  var
    input: RawByteString;
    whole, got: string;
    dropped: Boolean;
    count, k: Integer;
  begin
    input := TbReadFixture(AFile);
    whole := RunSse(input, fmWhole, 0, dropped, count);
    AssertEquals('E13: events in ' + AFile, AEvents, count);
    AssertFalse('E13: nothing dropped in ' + AFile, dropped);
    got := RunSse(input, fmBytes, 0, dropped, count);
    AssertEquals('E13: byte by byte, ' + AFile, whole, got);
    for k := 1 to Length(input) - 1 do
    begin
      got := RunSse(input, fmSplit, k, dropped, count);
      AssertEquals('E13: ' + AFile + ' cut after byte ' + IntToStr(k), whole, got);
    end;
  end;

begin
  One('openai-ok.sse', 7);
  One('anthropic-ok.sse', 13);
end;

{ E14: a line longer than MaxLine ends the reading -- also one that has not ended yet }
procedure TTbSseTests.TestALineHasALimit;
var
  log: TSseLog;
  p: TTbSseParser;
begin
  AssertEquals('E14: 1 MB by default', 1024 * 1024, TbSseMaxLine);
  log := TSseLog.Create;
  p := TTbSseParser.Create(@log.OnEvent);
  try
    p.MaxLine := 20;
    p.Feed('data: short'#10#10);
    AssertEquals('E14: a short line is fine', 'message=short'#1, log.Text);
    p.Feed('data: ' + StringOfChar('x', 30));       { no line break yet }
    AssertTrue('E14: an open line over the limit', p.Overflow <> '');
    p.Feed(#10#10'data: after'#10#10);
    p.Finish;
    AssertEquals('E14: nothing after it', 'message=short'#1, log.Text);
  finally
    p.Free;
    log.Free;
  end;
  log := TSseLog.Create;
  p := TTbSseParser.Create(@log.OnEvent);
  try
    p.MaxLine := 20;
    p.Feed('data: ' + StringOfChar('x', 30) + #10#10'data: after'#10#10);
    AssertTrue('E14: a whole line over the limit', p.Overflow <> '');
    AssertEquals('E14: no event from it or after it', '', log.Text);
  finally
    p.Free;
    log.Free;
  end;
end;

{ E15: an event whose data lines add up to more than MaxEvent ends the reading }
procedure TTbSseTests.TestAnEventHasALimit;
var
  log: TSseLog;
  p: TTbSseParser;
  i: Integer;
begin
  AssertEquals('E15: 4 MB by default', 4 * 1024 * 1024, TbSseMaxEvent);
  log := TSseLog.Create;
  p := TTbSseParser.Create(@log.OnEvent);
  try
    p.MaxLine := 20;
    p.MaxEvent := 50;
    for i := 1 to 6 do
      p.Feed('data: ' + StringOfChar('x', 10) + #10);     { each line under 20, 66 in all }
    p.Feed(#10);
    p.Finish;
    AssertTrue('E15: over the limit', p.Overflow <> '');
    AssertEquals('E15: not dispatched', '', log.Text);
  finally
    p.Free;
    log.Free;
  end;
end;

{ ---- TTbAiFormatTests ---- }

function Profile(AFormat: TTbAiFormat; const ABase: string; AMax: Integer): TTbAiProfile;
begin
  Result := Default(TTbAiProfile);
  Result.Format := AFormat;
  Result.BaseUrl := ABase;
  Result.Model := 'm-1';
  Result.MaxOutput := AMax;
end;

function HasLine(const AList: TStringArray; const S: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to High(AList) do
    if AList[i] = S then
      Exit(True);
end;

function HasPrefix(const AList: TStringArray; const S: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to High(AList) do
    if SameText(Copy(AList[i], 1, Length(S)), S) then
      Exit(True);
end;

procedure TTbAiFormatTests.TestTheEndpoint;
begin
  AssertEquals('A1', 'https://api.openai.com/v1/chat/completions',
    TbEndpointUrl(Profile(tafOpenAI, 'https://api.openai.com/v1', 0)));
  AssertEquals('A1: a trailing slash', 'https://api.openai.com/v1/chat/completions',
    TbEndpointUrl(Profile(tafOpenAI, 'https://api.openai.com/v1/', 0)));
  AssertEquals('A1: already complete', 'http://h/v1/chat/completions',
    TbEndpointUrl(Profile(tafOpenAI, 'http://h/v1/chat/completions', 0)));
  AssertEquals('A1: Anthropic', 'https://api.anthropic.com/v1/messages',
    TbEndpointUrl(Profile(tafAnthropic, 'https://api.anthropic.com/v1', 0)));
  AssertEquals('A1: Anthropic, complete', 'https://api.anthropic.com/v1/messages',
    TbEndpointUrl(Profile(tafAnthropic, 'https://api.anthropic.com/v1/messages', 0)));
end;

procedure TTbAiFormatTests.TestTheHeaders;
var
  h: TStringArray;
begin
  h := TbRequestHeaders(Profile(tafOpenAI, 'x', 0), 'k');
  AssertTrue('A2: bearer', HasLine(h, 'Authorization: Bearer k'));
  AssertTrue('A2: json', HasLine(h, 'Content-Type: application/json'));
  h := TbRequestHeaders(Profile(tafOpenAI, 'x', 0), '');
  AssertFalse('A2: no key, no Authorization at all', HasPrefix(h, 'Authorization'));
  h := TbRequestHeaders(Profile(tafAnthropic, 'x', 0), 'k');
  AssertTrue('A2: x-api-key', HasLine(h, 'x-api-key: k'));
  AssertTrue('A2: the version', HasLine(h, 'anthropic-version: 2023-06-01'));
  AssertTrue('A2: json, Anthropic', HasLine(h, 'Content-Type: application/json'));
  AssertFalse('A2: no bearer for Anthropic', HasPrefix(h, 'Authorization'));
end;

{ byte for byte, whatever code page either side is marked with }
function SameBytes(const A, B: RawByteString): Boolean;
begin
  Result := (Length(A) = Length(B)) and ((A = '') or CompareMem(@A[1], @B[1], Length(A)));
end;

procedure TTbAiFormatTests.TestTheBody;
const
  cDesc = 'warm ' + cChinese + ' "quoted" back\slash'#10'next'#9'tab';
var
  msgs: TTbChatMessages;
  body: RawByteString;
  d: TJSONData;
  o: TJSONObject;
  arr: TJSONArray;
  i: Integer;
  desc, chinese: string;
begin
  { through variables: a constant compared with a UTF8String is converted at compile time
    from the compiler's code page, which is not what the bytes mean }
  desc := cDesc;
  chinese := cChinese;
  SetLength(msgs, 3);
  msgs[0] := TbChatMessage(tcrUser, desc);
  msgs[1] := TbChatMessage(tcrAssistant, 'first answer');
  msgs[2] := TbChatMessage(tcrUser, 'again');

  body := TbRequestBody(Profile(tafOpenAI, 'x', 0), 'SYS', msgs);
  d := GetJSON(body);
  try
    o := d as TJSONObject;
    AssertTrue('A3: no max_tokens when 0', o.Find('max_tokens') = nil);
    AssertTrue('A3: no temperature', o.Find('temperature') = nil);
    AssertTrue('A3: stream', o.Booleans['stream']);
    AssertEquals('A3: model', 'm-1', o.Strings['model']);
    arr := o.Arrays['messages'];
    AssertEquals('A3: system + three', 4, arr.Count);
    AssertEquals('A3: system first', 'system', arr.Objects[0].Strings['role']);
    AssertEquals('A3: the system prompt', 'SYS', arr.Objects[0].Strings['content']);
    AssertEquals('A3: user', 'user', arr.Objects[1].Strings['role']);
    AssertEquals('A3: assistant', 'assistant', arr.Objects[2].Strings['role']);
    AssertEquals('A3: user again', 'user', arr.Objects[3].Strings['role']);
    AssertTrue('A3: the description comes back as it was',
      SameBytes(arr.Objects[1].Strings['content'], desc));
  finally
    d.Free;
  end;
  AssertTrue('A3: Chinese is UTF-8 in the body, not escaped', Pos(RawByteString(chinese), body) > 0);

  body := TbRequestBody(Profile(tafOpenAI, 'x', 8192), 'SYS', msgs);
  d := GetJSON(body);
  try
    AssertEquals('A3: max_tokens when set', 8192, (d as TJSONObject).Integers['max_tokens']);
  finally
    d.Free;
  end;

  body := TbRequestBody(Profile(tafAnthropic, 'x', 0), 'SYS', msgs);
  d := GetJSON(body);
  try
    o := d as TJSONObject;
    AssertEquals('A3: Anthropic system at the top', 'SYS', o.Strings['system']);
    AssertEquals('A3: Anthropic max_tokens when 0', TbAnthropicDefaultMaxOutput, o.Integers['max_tokens']);
    AssertEquals('A3: the default is 32000', 32000, TbAnthropicDefaultMaxOutput);
    AssertTrue('A3: Anthropic stream', o.Booleans['stream']);
    AssertTrue('A3: Anthropic, no temperature', o.Find('temperature') = nil);
    arr := o.Arrays['messages'];
    AssertEquals('A3: Anthropic messages', 3, arr.Count);
    for i := 0 to arr.Count - 1 do
      AssertTrue('A3: no system message', arr.Objects[i].Strings['role'] <> 'system');
    AssertTrue('A3: Anthropic description', SameBytes(arr.Objects[0].Strings['content'], desc));
  finally
    d.Free;
  end;
end;

procedure TTbAiFormatTests.TestAnOpenAIStream;
var
  log: TDeltaLog;
begin
  log := ReadSample('openai-ok.sse', tafOpenAI);
  try
    AssertTrue('A4: the whole answer',
      log.JoinedText = 'Here is the theme, ' + cChinese + '.'#10'```tycss'#10 +
        ':root { --accent: #2563EB; } /* ' + cPalette + ' */'#10'```');
    AssertEquals('A4: four text pieces', 4, log.Count(tspText));
    AssertTrue('A4: it ends with done', log.LastMeaningful = tspDone);
  finally
    log.Free;
  end;
end;

procedure TTbAiFormatTests.TestReasoningIsThinking;
var
  log: TDeltaLog;
begin
  log := ReadSample('deepseek-reasoning.sse', tafOpenAI);
  try
    AssertTrue('A5: thinking', log.Count(tspThinking) > 0);
    AssertEquals('A5: only the content', '```tycss'#10':root { --accent: #10B981; }'#10'```',
      log.JoinedText);
    AssertTrue('A5: done', log.Has(tspDone));
  finally
    log.Free;
  end;
end;

procedure TTbAiFormatTests.TestEscapedCharacters;
var
  log: TDeltaLog;
  i: Integer;
  chinese, palette: Boolean;
begin
  log := ReadSample('openai-ok.sse', tafOpenAI);
  try
    chinese := False;
    palette := False;
    for i := 0 to High(log.Kinds) do
      if log.Kinds[i] = tspText then
      begin
        if Pos(cChinese, log.Texts[i]) > 0 then chinese := True;
        if Pos(cPalette, log.Texts[i]) > 0 then palette := True;
      end;
    AssertTrue('A6: 中文 is 中文 in UTF-8', chinese);
    AssertTrue('A6: a surrogate pair is one UTF-8 character', palette);
  finally
    log.Free;
  end;
end;

procedure TTbAiFormatTests.TestOpenAICutOffAndError;
var
  log: TDeltaLog;
  i: Integer;
  found: Boolean;
begin
  log := ReadSample('openai-length.sse', tafOpenAI);
  try
    AssertTrue('A7: cut off', log.Has(tspTruncated));
  finally
    log.Free;
  end;
  log := ReadSample('openai-error-midstream.sse', tafOpenAI);
  try
    found := False;
    for i := 0 to High(log.Kinds) do
      if (log.Kinds[i] = tspError) and (Pos('server had an error', log.Texts[i]) > 0) then
        found := True;
    AssertTrue('A7: the error mid-stream', found);
  finally
    log.Free;
  end;
end;

procedure TTbAiFormatTests.TestAnAnthropicStream;
var
  log: TDeltaLog;
  i: Integer;
begin
  log := ReadSample('anthropic-ok.sse', tafAnthropic);
  try
    AssertEquals('A8: the text',
      'Warmer colours.'#10'```tycss'#10'@mode light { :root { --accent: #C2410C; } }'#10'```',
      log.JoinedText);
    AssertTrue('A8: thinking', log.Count(tspThinking) > 0);
    for i := 0 to log.Names.Count - 1 do
      if log.Names[i] = 'ping' then
        AssertTrue('A8: ping is nothing', log.Kinds[i] = tspNone);
    AssertTrue('A8: done last', log.LastMeaningful = tspDone);
  finally
    log.Free;
  end;
end;

procedure TTbAiFormatTests.TestAnthropicEnds;
var
  log: TDeltaLog;
  i: Integer;
  found: Boolean;
begin
  log := ReadSample('anthropic-max-tokens.sse', tafAnthropic);
  try
    AssertTrue('A9: max_tokens is cut off', log.Has(tspTruncated));
  finally
    log.Free;
  end;
  log := ReadSample('anthropic-refusal.sse', tafAnthropic);
  try
    AssertTrue('A9: refusal', log.Has(tspRefused));
  finally
    log.Free;
  end;
  log := ReadSample('anthropic-error.sse', tafAnthropic);
  try
    found := False;
    for i := 0 to High(log.Kinds) do
      if (log.Kinds[i] = tspError) and (log.Texts[i] = 'Overloaded') then
        found := True;
    AssertTrue('A9: the error says Overloaded', found);
  finally
    log.Free;
  end;
end;

procedure TTbAiFormatTests.TestErrorBodies;
var
  s: string;
begin
  AssertTrue('A10: OpenAI', Pos('Incorrect API key provided:',
    TbErrorBodyMessage(TbReadFixture('openai-401.json'))) = 1);
  AssertEquals('A10: Anthropic', 'invalid x-api-key', TbErrorBodyMessage(TbReadFixture('anthropic-401.json')));
  AssertEquals('A10: Ollama', 'model "qwen9" not found, try pulling it first',
    TbErrorBodyMessage(TbReadFixture('ollama-404.json')));
  AssertEquals('A10: a string error', 'boom', TbErrorBodyMessage('{"error":"boom"}'));
  s := TbErrorBodyMessage('<html>502 Bad Gateway</html>');
  AssertTrue('A10: not JSON: the start of it', Pos('<html>502', s) = 1);
  AssertTrue('A10: at most 200 bytes', Length(s) <= 200);
  s := TbErrorBodyMessage(StringOfChar('x', 500));
  AssertTrue('A10: a long text is cut', Length(s) <= 200);
end;

procedure TTbAiFormatTests.TestAWholeReply;
var
  t: string;
begin
  AssertTrue('A11: OpenAI', TbParseWholeReply(tafOpenAI, TbReadFixture('openai-whole.json'), t));
  AssertEquals('A11: OpenAI text', 'Done.'#10'```tycss'#10':root { --accent: #7C3AED; }'#10'```', t);
  AssertTrue('A11: Anthropic', TbParseWholeReply(tafAnthropic, TbReadFixture('anthropic-whole.json'), t));
  AssertEquals('A11: Anthropic text', 'Done.'#10'```tycss'#10':root { --accent: #7C3AED; }'#10'```', t);
  AssertFalse('A11: something else', TbParseWholeReply(tafOpenAI, '{"x":1}', t));
  AssertFalse('A11: something else, Anthropic', TbParseWholeReply(tafAnthropic, '{"x":1}', t));
end;

{ after the phase 3 reviews: data that is not JSON is a heartbeat -- nothing, not an error
  (a proxy's "data: ping" or an empty data line failed a whole, complete answer) }
procedure TTbAiFormatTests.TestNotJsonIsAnError;
var
  ev: TTbSseEvent;
  d: TTbStreamDelta;
  f: TTbAiFormat;
  i: Integer;
const
  cBeats: array[0..3] of string = ('hello', '', 'ping', ' ');
begin
  ev.Name := 'message';
  for f := Low(TTbAiFormat) to High(TTbAiFormat) do
    for i := 0 to High(cBeats) do
    begin
      ev.Data := cBeats[i];
      d := TbParseStreamEvent(f, ev);
      AssertTrue(Format('A12: "%s" is nothing (%d)', [cBeats[i], Ord(f)]), d.Kind = tspNone);
      AssertTrue(Format('A12: "%s" ends nothing (%d)', [cBeats[i], Ord(f)]), d.Ends = tspNone);
      AssertTrue(Format('A12: "%s" is marked (%d)', [cBeats[i], Ord(f)]), d.NotJson);
    end;
  ev.Data := '{"choices":[]}';
  AssertFalse('A12: JSON is not marked', TbParseStreamEvent(tafOpenAI, ev).NotJson);
end;

initialization
  RegisterTest(TTbSseTests);
  RegisterTest(TTbAiFormatTests);
end.
