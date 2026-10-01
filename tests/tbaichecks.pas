unit tbaichecks;
{ The AI transport's checks, written once and run twice: by tytests on Windows (WinHTTP;
  test.themebuilder.http, test.themebuilder.aiclient) and by the WSL console program
  tools/themebuilder-curl-wsl (libcurl) -- "the same criterion on the other transport" is
  then the same code, not a copy that drifts.

  Each check sets up its own local server (tbfakehttp), runs the transport or the client on
  a worker thread (TTbHttpRun / TTbAiRun) while this thread waits, and returns True, or
  False with the reason in AWhy. The numbers (H1 ...) are the phase 3 plan's.

  RTL / FCL only (it is compiled in WSL). }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, SyncObjs, tbhttp, tbfakehttp, tbaiformat, tbaiclient, tbaisettings;

type
  { one Execute on a worker thread, with everything the checks look at afterwards }
  TTbHttpRun = class(TThread)
  private
    FLock: TCriticalSection;
    FStart: QWord;
    procedure DoStatus(AStatus: Integer);
    function DoData(const AData: RawByteString): Boolean;
  protected
    procedure Execute; override;
  public
    Transport: TTbHttpTransport;
    Request: TTbHttpRequest;
    Outcome: TTbHttpResult;
    Received: RawByteString;
    DataCalls, StatusCalls: Integer;
    StatusFirst: Boolean;          { the status came before any data }
    FirstDataMs, EndMs: Int64;     { from the start; -1 = never }
    RefuseData: Boolean;           { OnData answers False (stop) }
    constructor Create(const ARequest: TTbHttpRequest);
    destructor Destroy; override;
    procedure Go;
    { waits (CheckSynchronize) until Execute returned; False after AMs }
    function WaitDone(AMs: Integer): Boolean;
    function ElapsedMs: Int64;
    function DataCount: Integer;
  end;

  { one TTbAiClient.Run on a worker thread }
  TTbAiRun = class(TThread)
  private
    FLock: TCriticalSection;
    procedure DoDelta(Sender: TObject; APiece: TTbStreamPiece; const AText: string);
  protected
    procedure Execute; override;
  public
    Client: TTbAiClient;
    Profile: TTbAiProfile;
    Outcome: TTbAiResult;
    TextPieces, ThinkingPieces, OffWorker: Integer;   { OffWorker: deltas on the main thread }
    Streamed: string;
    constructor Create(const AProfile: TTbAiProfile; const AKey: string);
    destructor Destroy; override;
    function WaitDone(AMs: Integer): Boolean;
    function TextCount: Integer;
  end;

var
  { where tests/fixtures/themebuilder/ai is, with a trailing delimiter; the caller sets it }
  TbAiFixtureDir: string = '';
  { how long a cancelled Execute may take to come back: WinHTTP closes the handle at once;
    libcurl notices in its progress callback, about once a second }
  TbCancelGraceMs: Integer = 1000;

function TbLoadFixture(const AName: string): RawByteString;

function HttpCheckPlain(out AWhy: string): Boolean;          { H1 }
function HttpCheckStreamed(out AWhy: string): Boolean;       { H2 }
function HttpCheckStatus(ACode: Integer; out AWhy: string): Boolean;   { H3, H4 }
function HttpCheckBroken(out AWhy: string): Boolean;         { H5 }
function HttpCheckIdleTimeout(out AWhy: string): Boolean;    { H6 }
function HttpCheckCannotConnect(out AWhy: string): Boolean;  { H7 }
function HttpCheckCancel(out AWhy: string): Boolean;         { H8 }
function HttpCheckRefuseData(out AWhy: string): Boolean;     { H9 }
function HttpCheckLocalhost(out AWhy: string): Boolean;      { H10 }
function HttpCheckBigBody(out AWhy: string): Boolean;        { H13 }

{ the AI client against the local server: the plan's C numbers }
function AiCheckOpenAIStream(out AWhy: string): Boolean;      { C1 }
function AiCheckAnthropicStream(out AWhy: string): Boolean;   { C2 }
function AiCheckKeyIsScrubbed(out AWhy: string): Boolean;     { C3 }
function AiCheckRateLimit(out AWhy: string): Boolean;         { C4 }
function AiCheckNotFound(out AWhy: string): Boolean;          { C5 }
function AiCheckServerErrors(out AWhy: string): Boolean;      { C6 }
function AiCheckBroken(out AWhy: string): Boolean;            { C7 }
function AiCheckNeverFinished(out AWhy: string): Boolean;     { C8 }
function AiCheckTimeout(out AWhy: string): Boolean;           { C9 }
function AiCheckStreamError(out AWhy: string): Boolean;       { C10 }
function AiCheckTruncated(out AWhy: string): Boolean;         { C11 }
function AiCheckRefused(out AWhy: string): Boolean;           { C12 }
function AiCheckNotStreamed(out AWhy: string): Boolean;       { C13 }
function AiCheckBadFormat(out AWhy: string): Boolean;         { C14 }
function AiCheckCancel(out AWhy: string): Boolean;            { C15 }
function AiCheckNoKeyNoHeader(out AWhy: string): Boolean;     { C16 }
{ after the phase 3 reviews }
function AiCheckRedirects(out AWhy: string): Boolean;         { C18 }
function AiCheckInsecureKey(out AWhy: string): Boolean;       { C19 }

type
  { a transport that only counts being asked and answers "cannot connect": installed with
    TbRecordTransports so a request that must not go out never reaches the network }
  TTbRecordingTransport = class(TTbHttpTransport)
  public
    function Execute(const ARequest: TTbHttpRequest; AOnStatus: TTbHttpStatusEvent;
      AOnData: TTbHttpDataEvent): TTbHttpResult; override;
    procedure Cancel; override;
  end;

var
  TbRecordedRequests: Integer = 0;    { Execute calls on recording transports }
  TbRecordedUrl: string = '';

{ AOn: TbCreateTransport hands out recording transports (and the count starts at 0) }
procedure TbRecordTransports(AOn: Boolean);

{ the AI settings: the plan's K numbers (the Windows-only ones are in the test unit) }
function TbAiTempDir: string;                                 { a fresh folder }
procedure TbAiRemoveDir(const ADir: string);
function SettingsCheckRoundTrip(out AWhy: string): Boolean;   { K1 }
{$IFDEF UNIX}
function SettingsCheckUnixKeyFile(out AWhy: string): Boolean; { K2, Unix }
function SettingsCheckWideKeyFile(out AWhy: string): Boolean; { K9 }
function SettingsCheckPrivateFile(out AWhy: string): Boolean; { K10 }
{$ENDIF}

implementation

uses
  fpjson, jsonparser{$IFDEF UNIX}, BaseUnix{$ENDIF};

const
  cChinese = #$E4#$B8#$AD#$E6#$96#$87;    { 中文 in UTF-8 }

function TbLoadFixture(const AName: string): RawByteString;
var
  fs: TFileStream;
begin
  Result := '';
  fs := TFileStream.Create(TbAiFixtureDir + AName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, fs.Size);
    if fs.Size > 0 then
      fs.ReadBuffer(Result[1], fs.Size);
  finally
    fs.Free;
  end;
end;

{ ---- TTbHttpRun ---- }

constructor TTbHttpRun.Create(const ARequest: TTbHttpRequest);
var
  reason: string;
begin
  FreeOnTerminate := False;
  inherited Create(True);
  FLock := TCriticalSection.Create;
  Request := ARequest;
  FirstDataMs := -1;
  EndMs := -1;
  Transport := TbCreateTransport(reason);
  if Transport = nil then
    raise Exception.Create('no transport: ' + reason);
end;

destructor TTbHttpRun.Destroy;
begin
  if (Transport <> nil) and (FStart <> 0) and not Finished then
  begin
    Transport.Cancel;
    WaitFor;
  end;
  Transport.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TTbHttpRun.Go;
begin
  FStart := GetTickCount64;
  Start;
end;

function TTbHttpRun.ElapsedMs: Int64;
begin
  Result := Int64(GetTickCount64 - FStart);
end;

procedure TTbHttpRun.DoStatus(AStatus: Integer);
begin
  FLock.Enter;
  try
    Inc(StatusCalls);
    if DataCalls = 0 then
      StatusFirst := True;
  finally
    FLock.Leave;
  end;
end;

function TTbHttpRun.DoData(const AData: RawByteString): Boolean;
begin
  FLock.Enter;
  try
    Inc(DataCalls);
    if FirstDataMs < 0 then
      FirstDataMs := ElapsedMs;
    Received := Received + AData;
    Result := not RefuseData;
  finally
    FLock.Leave;
  end;
end;

function TTbHttpRun.DataCount: Integer;
begin
  FLock.Enter;
  try
    Result := DataCalls;
  finally
    FLock.Leave;
  end;
end;

procedure TTbHttpRun.Execute;
begin
  try
    Outcome := Transport.Execute(Request, @DoStatus, @DoData);
  except
    on E: Exception do
    begin
      Outcome.Error := hekOther;
      Outcome.Detail := 'raised: ' + E.Message;
    end;
  end;
  EndMs := ElapsedMs;
end;

function TTbHttpRun.WaitDone(AMs: Integer): Boolean;
var
  t0: QWord;
begin
  t0 := GetTickCount64;
  while not Finished do
  begin
    if GetTickCount64 - t0 > QWord(AMs) then
      Exit(False);
    CheckSynchronize(10);
  end;
  Result := True;
end;

{ ---- helpers ---- }

function NewRequest(const AUrl: string): TTbHttpRequest;
begin
  Result := Default(TTbHttpRequest);
  Result.Url := AUrl;
  Result.IdleTimeoutMs := 10000;
end;

function KindName(AKind: TTbHttpErrorKind): string;
begin
  WriteStr(Result, AKind);
end;

function Fail(out AWhy: string; const AText: string): Boolean;
begin
  AWhy := AText;
  Result := False;
end;

function Describe(ARun: TTbHttpRun): string;
begin
  Result := Format('status %d, %s (%s), %d data calls, %d bytes, %d ms',
    [ARun.Outcome.Status, KindName(ARun.Outcome.Error), ARun.Outcome.Detail, ARun.DataCalls,
     Length(ARun.Received), ARun.EndMs]);
end;

{ ---- the checks ---- }

function CheckPlainAt(AServer: TTbFakeHttpServer; const AUrl, APath: string;
  AMaxMs: Integer; out AWhy: string): Boolean;
var
  req: TTbHttpRequest;
  run: TTbHttpRun;
  got: TTbFakeRequest;
  body: RawByteString;
begin
  body := '{"q":"' + cChinese + '"}';
  AServer.Script([FakeSend(FakeHead(200, 'application/json', False, '{"ok":1}'))]);
  req := NewRequest(AUrl);
  req.Headers := ['Content-Type: application/json', 'Authorization: Bearer t-123'];
  req.Body := body;
  run := TTbHttpRun.Create(req);
  try
    run.Go;
    if not run.WaitDone(10000) then Exit(Fail(AWhy, 'did not finish in 10 s'));
    if run.Outcome.Error <> hekNone then Exit(Fail(AWhy, 'failed: ' + Describe(run)));
    if run.Outcome.Status <> 200 then Exit(Fail(AWhy, 'status: ' + Describe(run)));
    if run.Received <> '{"ok":1}' then Exit(Fail(AWhy, 'received: ' + run.Received));
    if (AMaxMs > 0) and (run.EndMs > AMaxMs) then
      Exit(Fail(AWhy, Format('took %d ms (at most %d)', [run.EndMs, AMaxMs])));
    if run.StatusCalls <> 1 then Exit(Fail(AWhy, Format('OnStatus %d times', [run.StatusCalls])));
    if not run.StatusFirst then Exit(Fail(AWhy, 'OnStatus came after OnData'));
    got := AServer.LastRequest;
    if got.Method <> 'POST' then Exit(Fail(AWhy, 'method ' + got.Method));
    if got.Path <> APath then Exit(Fail(AWhy, 'path ' + got.Path));
    if AServer.HeaderValue('content-type') <> 'application/json' then
      Exit(Fail(AWhy, 'content-type: ' + AServer.HeaderValue('content-type')));
    if AServer.HeaderValue('authorization') <> 'Bearer t-123' then
      Exit(Fail(AWhy, 'authorization: ' + AServer.HeaderValue('authorization')));
    if got.Body <> body then Exit(Fail(AWhy, 'the body arrived as ' + got.Body));
    Result := True;
    AWhy := '';
  finally
    run.Free;
  end;
end;

function HttpCheckPlain(out AWhy: string): Boolean;
var
  srv: TTbFakeHttpServer;
begin
  srv := TTbFakeHttpServer.Create;
  try
    Result := CheckPlainAt(srv, srv.Url('/v1/x?y=1'), '/v1/x?y=1', 0, AWhy);
  finally
    srv.Free;
  end;
end;

function HttpCheckLocalhost(out AWhy: string): Boolean;
var
  srv: TTbFakeHttpServer;
begin
  srv := TTbFakeHttpServer.Create;
  try
    Result := CheckPlainAt(srv, 'http://localhost:' + IntToStr(srv.Port) + '/x', '/x', 3000, AWhy);
  finally
    srv.Free;
  end;
end;

function HttpCheckStreamed(out AWhy: string): Boolean;
var
  srv: TTbFakeHttpServer;
  run: TTbHttpRun;
begin
  Result := False;
  srv := TTbFakeHttpServer.Create;
  try
    srv.Script([FakeSend(FakeHead(200, 'text/event-stream', True)), FakeSend(FakeChunk('a')),
      FakeSleep(300), FakeSend(FakeChunk('b')), FakeSleep(300), FakeSend(FakeChunk('c')),
      FakeSend(FakeLastChunk)]);
    run := TTbHttpRun.Create(NewRequest(srv.Url('/s')));
    try
      run.Go;
      if not run.WaitDone(10000) then Exit(Fail(AWhy, 'did not finish in 10 s'));
      if run.Outcome.Error <> hekNone then Exit(Fail(AWhy, 'failed: ' + Describe(run)));
      if run.Received <> 'abc' then Exit(Fail(AWhy, 'received ' + run.Received));
      { the server really slept: else "came early" proves nothing }
      if run.EndMs < 550 then Exit(Fail(AWhy, Format('the whole reply took only %d ms', [run.EndMs])));
      if run.DataCalls < 3 then Exit(Fail(AWhy, Format('%d data calls', [run.DataCalls])));
      if run.EndMs - run.FirstDataMs < 450 then
        Exit(Fail(AWhy, Format('the first bytes came at %d ms, the end at %d ms: not streamed',
          [run.FirstDataMs, run.EndMs])));
      Result := True;
      AWhy := '';
    finally
      run.Free;
    end;
  finally
    srv.Free;
  end;
end;

function HttpCheckStatus(ACode: Integer; out AWhy: string): Boolean;
const
  cBody = '{"error":{"message":"bad key"}}';
var
  srv: TTbFakeHttpServer;
  run: TTbHttpRun;
begin
  Result := False;
  srv := TTbFakeHttpServer.Create;
  try
    srv.Script([FakeSend(FakeHead(ACode, 'application/json', False, cBody))]);
    run := TTbHttpRun.Create(NewRequest(srv.Url('/e')));
    try
      run.Go;
      if not run.WaitDone(10000) then Exit(Fail(AWhy, 'did not finish in 10 s'));
      if run.Outcome.Error <> hekNone then Exit(Fail(AWhy, 'an error: ' + Describe(run)));
      if run.Outcome.Status <> ACode then Exit(Fail(AWhy, 'status: ' + Describe(run)));
      if run.Received <> cBody then Exit(Fail(AWhy, 'the body: ' + run.Received));
      Result := True;
      AWhy := '';
    finally
      run.Free;
    end;
  finally
    srv.Free;
  end;
end;

function HttpCheckBroken(out AWhy: string): Boolean;
var
  srv: TTbFakeHttpServer;
  run: TTbHttpRun;
begin
  Result := False;
  srv := TTbFakeHttpServer.Create;
  try
    srv.Script([FakeSend(FakeHead(200, 'text/event-stream', True)), FakeSend(FakeChunk('a')),
      FakeSleep(100), FakeClose]);
    run := TTbHttpRun.Create(NewRequest(srv.Url('/b')));
    try
      run.Go;
      if not run.WaitDone(10000) then Exit(Fail(AWhy, 'did not finish in 10 s'));
      if run.Outcome.Error <> hekBroken then Exit(Fail(AWhy, 'not broken: ' + Describe(run)));
      if run.Received <> 'a' then Exit(Fail(AWhy, 'received ' + run.Received));
      if run.Outcome.Status <> 200 then Exit(Fail(AWhy, 'the status went: ' + Describe(run)));
      Result := True;
      AWhy := '';
    finally
      run.Free;
    end;
  finally
    srv.Free;
  end;
end;

function HttpCheckIdleTimeout(out AWhy: string): Boolean;
var
  srv: TTbFakeHttpServer;
  run: TTbHttpRun;
  req: TTbHttpRequest;
begin
  Result := False;
  srv := TTbFakeHttpServer.Create;
  try
    srv.Script([FakeSend(FakeHead(200, 'text/event-stream', True)), FakeSend(FakeChunk('a')),
      FakeHold]);
    req := NewRequest(srv.Url('/t'));
    req.IdleTimeoutMs := 1000;
    run := TTbHttpRun.Create(req);
    try
      run.Go;
      if not run.WaitDone(10000) then Exit(Fail(AWhy, 'no timeout in 10 s'));
      if run.Outcome.Error <> hekTimeout then Exit(Fail(AWhy, 'not a timeout: ' + Describe(run)));
      if (run.EndMs < 900) or (run.EndMs > 4000) then
        Exit(Fail(AWhy, Format('timed out after %d ms (0.9 - 4 s)', [run.EndMs])));
      Result := True;
      AWhy := '';
    finally
      run.Free;
    end;
  finally
    srv.Free;
  end;
end;

function HttpCheckCannotConnect(out AWhy: string): Boolean;
var
  run: TTbHttpRun;
begin
  Result := False;
  run := TTbHttpRun.Create(NewRequest('http://127.0.0.1:' + IntToStr(FakeDeadPort) + '/'));
  try
    run.Go;
    if not run.WaitDone(10000) then Exit(Fail(AWhy, 'did not finish in 10 s'));
    if run.Outcome.Error <> hekCannotConnect then Exit(Fail(AWhy, 'not "cannot connect": ' + Describe(run)));
    if run.EndMs >= 3000 then Exit(Fail(AWhy, Format('took %d ms', [run.EndMs])));
    Result := True;
    AWhy := '';
  finally
    run.Free;
  end;
end;

function HttpCheckCancel(out AWhy: string): Boolean;
var
  srv: TTbFakeHttpServer;
  run: TTbHttpRun;
  req: TTbHttpRequest;
  t0, cancelAt: QWord;
begin
  Result := False;
  srv := TTbFakeHttpServer.Create;
  try
    srv.Script([FakeSend(FakeHead(200, 'text/event-stream', True)), FakeSend(FakeChunk('a')),
      FakeHold]);
    req := NewRequest(srv.Url('/c'));
    req.IdleTimeoutMs := 30000;
    run := TTbHttpRun.Create(req);
    try
      run.Go;
      t0 := GetTickCount64;
      while (run.DataCount = 0) and (GetTickCount64 - t0 < 5000) and not run.Finished do
        CheckSynchronize(10);
      if run.DataCount = 0 then Exit(Fail(AWhy, 'no data before cancelling: ' + Describe(run)));
      while GetTickCount64 - t0 < 300 do
        CheckSynchronize(10);
      cancelAt := GetTickCount64;
      run.Transport.Cancel;      { from this thread, while the worker is blocked }
      if not run.WaitDone(10000) then Exit(Fail(AWhy, 'Cancel did not stop it in 10 s'));
      if run.Outcome.Error <> hekCancelled then Exit(Fail(AWhy, 'not cancelled: ' + Describe(run)));
      if GetTickCount64 - cancelAt > QWord(TbCancelGraceMs) then
        Exit(Fail(AWhy, Format('came back %d ms after Cancel (at most %d)',
          [GetTickCount64 - cancelAt, TbCancelGraceMs])));
      Result := True;
      AWhy := '';
    finally
      run.Free;
    end;
  finally
    t0 := GetTickCount64;
    srv.Free;     { must not hang on the held connection }
    if Result and (GetTickCount64 - t0 > 3000) then
    begin
      Result := False;
      AWhy := 'the server took long to stop';
    end;
  end;
end;

function HttpCheckRefuseData(out AWhy: string): Boolean;
var
  srv: TTbFakeHttpServer;
  run: TTbHttpRun;
begin
  Result := False;
  srv := TTbFakeHttpServer.Create;
  try
    srv.Script([FakeSend(FakeHead(200, 'text/event-stream', True)), FakeSend(FakeChunk('a')),
      FakeSleep(200), FakeSend(FakeChunk('b')), FakeSleep(200), FakeSend(FakeChunk('c')),
      FakeSend(FakeLastChunk)]);
    run := TTbHttpRun.Create(NewRequest(srv.Url('/r')));
    try
      run.RefuseData := True;
      run.Go;
      if not run.WaitDone(10000) then Exit(Fail(AWhy, 'did not finish in 10 s'));
      if run.Outcome.Error <> hekCancelled then Exit(Fail(AWhy, 'not cancelled: ' + Describe(run)));
      if run.DataCalls <> 1 then Exit(Fail(AWhy, Format('%d data calls after refusing the first',
        [run.DataCalls])));
      Result := True;
      AWhy := '';
    finally
      run.Free;
    end;
  finally
    srv.Free;
  end;
end;

function HttpCheckBigBody(out AWhy: string): Boolean;
var
  srv: TTbFakeHttpServer;
  run: TTbHttpRun;
  req: TTbHttpRequest;
begin
  Result := False;
  srv := TTbFakeHttpServer.Create;
  try
    srv.Script([FakeSend(FakeHead(200, 'application/json', False, '{}'))]);
    req := NewRequest(srv.Url('/big'));
    req.Body := StringOfChar('x', 200 * 1024);
    run := TTbHttpRun.Create(req);
    try
      run.Go;
      if not run.WaitDone(10000) then Exit(Fail(AWhy, 'did not finish in 10 s'));
      if run.Outcome.Error <> hekNone then Exit(Fail(AWhy, 'failed: ' + Describe(run)));
      if srv.LastRequest.Body <> req.Body then
        Exit(Fail(AWhy, Format('the server got %d bytes of %d', [Length(srv.LastRequest.Body),
          Length(req.Body)])));
      Result := True;
      AWhy := '';
    finally
      run.Free;
    end;
  finally
    srv.Free;
  end;
end;


{ ---- TTbAiRun ---- }

constructor TTbAiRun.Create(const AProfile: TTbAiProfile; const AKey: string);
begin
  FreeOnTerminate := False;
  inherited Create(True);
  FLock := TCriticalSection.Create;
  Profile := AProfile;
  Client := TTbAiClient.Create(AProfile, AKey);
end;

destructor TTbAiRun.Destroy;
begin
  if not Finished then
  begin
    Client.Cancel;
    WaitFor;
  end;
  Client.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TTbAiRun.DoDelta(Sender: TObject; APiece: TTbStreamPiece; const AText: string);
begin
  FLock.Enter;
  try
    if GetCurrentThreadId = MainThreadID then
      Inc(OffWorker);
    if APiece = tspText then
    begin
      Inc(TextPieces);
      Streamed := Streamed + AText;
    end
    else if APiece = tspThinking then
      Inc(ThinkingPieces);
  finally
    FLock.Leave;
  end;
end;

function TTbAiRun.TextCount: Integer;
begin
  FLock.Enter;
  try
    Result := TextPieces;
  finally
    FLock.Leave;
  end;
end;

procedure TTbAiRun.Execute;
var
  msgs: TTbChatMessages;
begin
  SetLength(msgs, 1);
  msgs[0] := TbChatMessage(tcrUser, 'make it blue');
  try
    Outcome := Client.Run('SYSTEM', msgs, @DoDelta);
  except
    on E: Exception do
    begin
      Outcome.Kind := aekOther;
      Outcome.Detail := 'raised: ' + E.Message;
    end;
  end;
end;

function TTbAiRun.WaitDone(AMs: Integer): Boolean;
var
  t0: QWord;
begin
  t0 := GetTickCount64;
  while not Finished do
  begin
    if GetTickCount64 - t0 > QWord(AMs) then
      Exit(False);
    CheckSynchronize(10);
  end;
  Result := True;
end;

{ ---- helpers for the C checks ---- }

type
  TTbIntArray = array of Integer;

const
  cOpenAIText = 'Here is the theme, ' + cChinese + '.'#10'```tycss'#10 +
    ':root { --accent: #2563EB; } /* '#$F0#$9F#$8E#$A8' */'#10'```';
  cAnthropicText = 'Warmer colours.'#10'```tycss'#10'@mode light { :root { --accent: #C2410C; } }'#10'```';
  cFakeKey = 'sk-test-0000';

function AiKindName(AKind: TTbAiErrorKind): string;
begin
  WriteStr(Result, AKind);
end;

function AiDescribe(ARun: TTbAiRun): string;
begin
  Result := Format('%s, status %d, detail "%s", %d text pieces, text "%s"',
    [AiKindName(ARun.Outcome.Kind), ARun.Outcome.Status, ARun.Outcome.Detail, ARun.TextPieces,
     Copy(ARun.Outcome.Text, 1, 60)]);
end;

function AiProfile(AServer: TTbFakeHttpServer; AFormat: TTbAiFormat): TTbAiProfile;
begin
  Result := Default(TTbAiProfile);
  Result.Id := 'test';
  Result.Name := 'test';
  Result.Format := AFormat;
  Result.BaseUrl := AServer.Url('/v1');
  Result.Model := 'm-1';
  Result.MaxOutput := 0;
  Result.TimeoutSec := 10;
end;

{ the start of the event (its "data:" or "event:" line) that holds AMark }
function EventStartOf(const AData, AMark: string): Integer;
var
  p: Integer;
begin
  p := Pos(AMark, AData);
  Result := 0;
  if p = 0 then Exit;
  while p > 1 do
  begin
    if ((AData[p - 1] = #10) or (AData[p - 1] = #13)) and
       ((Copy(AData, p, 6) = 'data: ') or (Copy(AData, p, 7) = 'event: ')) then
    begin
      { an "event:" line just above belongs to the same event }
      Result := p;
      if (p > 2) then
      begin
        Dec(p);
        if (AData[p] = #10) and (p > 1) and (AData[p - 1] = #13) then Dec(p);
        while (p > 1) and not (AData[p - 1] in [#10, #13]) do Dec(p);
        if Copy(AData, p, 7) = 'event: ' then
          Result := p;
      end;
      Exit;
    end;
    Dec(p);
  end;
end;

{ the reply streamed in pieces cut at ACuts (offsets the pieces start at), 50 ms apart }
procedure StreamPieces(AServer: TTbFakeHttpServer; const AData: RawByteString;
  const ACuts: array of Integer; AEnd: Boolean; AHoldAfter: Boolean = False);
var
  steps: array of TTbFakeStep;
  i, from, upto: Integer;

  procedure Add(const AStep: TTbFakeStep);
  begin
    SetLength(steps, Length(steps) + 1);
    steps[High(steps)] := AStep;
  end;

begin
  steps := nil;
  Add(FakeSend(FakeHead(200, 'text/event-stream', True)));
  from := 1;
  for i := 0 to Length(ACuts) do
  begin
    if i < Length(ACuts) then
      upto := ACuts[i]
    else
      upto := Length(AData) + 1;
    if upto > from then
    begin
      Add(FakeSend(FakeChunk(Copy(AData, from, upto - from))));
      Add(FakeSleep(50));
    end;
    from := upto;
  end;
  if AEnd then
    Add(FakeSend(FakeLastChunk))
  else if AHoldAfter then
    Add(FakeHold)
  else
    Add(FakeClose);
  AServer.Script(steps);
end;

function RunClient(AServer: TTbFakeHttpServer; const AProfile: TTbAiProfile; const AKey: string;
  out ARun: TTbAiRun; out AWhy: string): Boolean;
begin
  ARun := TTbAiRun.Create(AProfile, AKey);
  ARun.Start;
  Result := ARun.WaitDone(10000);
  if not Result then
    AWhy := 'the client did not finish in 10 s';
end;

{ a reply of one status and one body, run to its end; the caller checks }
function RunStatus(ACode: Integer; const ABody: RawByteString; AFormat: TTbAiFormat;
  const AKey: string; out ARun: TTbAiRun; out AWhy: string; AServer: TTbFakeHttpServer): Boolean;
begin
  AServer.Script([FakeSend(FakeHead(ACode, 'application/json', False, ABody))]);
  Result := RunClient(AServer, AiProfile(AServer, AFormat), AKey, ARun, AWhy);
end;

function ComparePtrInts(A, B: Pointer): Integer;
begin
  Result := PtrInt(A) - PtrInt(B);
end;

function CutsFor(const AData: RawByteString): TTbIntArray;
var
  p, i, n, c: Integer;
  list: TList;
begin
  list := TList.Create;
  try
    { inside the data line of the second content event }
    p := Pos('```tycss', AData);
    if p > 0 then
      list.Add(Pointer(PtrInt(p + 3)));
    { between a CR and the LF after it (when the sample uses CRLF) }
    p := Pos(#13#10, Copy(AData, Length(AData) div 3, MaxInt));
    if p > 0 then
      list.Add(Pointer(PtrInt(Length(AData) div 3 + p)));
    n := Length(AData);
    for i := 1 to 6 do
    begin
      if list.Count >= 6 then Break;
      c := (n * i) div 7;
      if list.IndexOf(Pointer(PtrInt(c))) < 0 then
        list.Add(Pointer(PtrInt(c)));
    end;
    list.Sort(@ComparePtrInts);
    SetLength(Result, list.Count);
    for i := 0 to list.Count - 1 do
      Result[i] := PtrInt(list[i]);
  finally
    list.Free;
  end;
end;

{ ---- the C checks ---- }

function AiCheckOpenAIStream(out AWhy: string): Boolean;
var
  srv: TTbFakeHttpServer;
  run: TTbAiRun;
  data: RawByteString;
  body: TJSONData;
begin
  Result := False;
  run := nil;
  srv := TTbFakeHttpServer.Create;
  try
    data := TbLoadFixture('openai-ok.sse');
    if Pos(#13#10, data) = 0 then Exit(Fail(AWhy, 'the sample has no CRLF to cut through'));
    StreamPieces(srv, data, CutsFor(data), True);
    if not RunClient(srv, AiProfile(srv, tafOpenAI), cFakeKey, run, AWhy) then Exit;
    if run.Outcome.Kind <> aekNone then Exit(Fail(AWhy, 'failed: ' + AiDescribe(run)));
    if run.Outcome.Text <> cOpenAIText then Exit(Fail(AWhy, 'the text: ' + run.Outcome.Text));
    if run.TextPieces < 4 then Exit(Fail(AWhy, Format('%d text pieces', [run.TextPieces])));
    if run.OffWorker > 0 then Exit(Fail(AWhy, 'pieces came on the main thread'));
    if srv.LastRequest.Path <> '/v1/chat/completions' then
      Exit(Fail(AWhy, 'the path ' + srv.LastRequest.Path));
    body := GetJSON(srv.LastRequest.Body);
    try
      if not ((body is TJSONObject) and (TJSONObject(body).Find('stream') <> nil) and
         TJSONObject(body).Booleans['stream']) then
        Exit(Fail(AWhy, 'no "stream": true in ' + srv.LastRequest.Body));
    finally
      body.Free;
    end;
    Result := True;
    AWhy := '';
  finally
    run.Free;
    srv.Free;
  end;
end;

function AiCheckAnthropicStream(out AWhy: string): Boolean;
var
  srv: TTbFakeHttpServer;
  run: TTbAiRun;
  data: RawByteString;
begin
  Result := False;
  run := nil;
  srv := TTbFakeHttpServer.Create;
  try
    data := TbLoadFixture('anthropic-ok.sse');
    StreamPieces(srv, data, CutsFor(data), True);
    if not RunClient(srv, AiProfile(srv, tafAnthropic), cFakeKey, run, AWhy) then Exit;
    if run.Outcome.Kind <> aekNone then Exit(Fail(AWhy, 'failed: ' + AiDescribe(run)));
    if run.Outcome.Text <> cAnthropicText then Exit(Fail(AWhy, 'the text: ' + run.Outcome.Text));
    if run.ThinkingPieces = 0 then Exit(Fail(AWhy, 'no thinking was reported'));
    if srv.HeaderValue('x-api-key') <> cFakeKey then Exit(Fail(AWhy, 'no x-api-key header'));
    if srv.HeaderValue('anthropic-version') = '' then Exit(Fail(AWhy, 'no anthropic-version header'));
    if srv.LastRequest.Path <> '/v1/messages' then Exit(Fail(AWhy, 'the path ' + srv.LastRequest.Path));
    Result := True;
    AWhy := '';
  finally
    run.Free;
    srv.Free;
  end;
end;

function AiCheckKeyIsScrubbed(out AWhy: string): Boolean;
const
  cKey = 'sk-proj-abcdefghijklmnopqrstuvwxyzab12';
var
  srv: TTbFakeHttpServer;
  run: TTbAiRun;
  body: RawByteString;
  sentence: string;
begin
  Result := False;
  run := nil;
  srv := TTbFakeHttpServer.Create;
  try
    body := TbLoadFixture('openai-401.json');
    { the service's message really quotes the key's last four }
    if Pos('ab12', body) = 0 then Exit(Fail(AWhy, 'the sample does not quote the key'));
    if not RunStatus(401, body, tafOpenAI, cKey, run, AWhy, srv) then Exit;
    if run.Outcome.Kind <> aekAuth then Exit(Fail(AWhy, 'not a key error: ' + AiKindName(run.Outcome.Kind)));
    if run.Outcome.Status <> 401 then Exit(Fail(AWhy, Format('status %d', [run.Outcome.Status])));
    sentence := TbAiErrorSentence(run.Outcome, run.Profile);
    if (Pos('ab12', run.Outcome.Detail) > 0) or (Pos('ab12', sentence) > 0) then
      Exit(Fail(AWhy, 'the key''s last four are still there'));
    if (Pos('sk-proj-a', run.Outcome.Detail) > 0) or (Pos('sk-proj-a', sentence) > 0) then
      Exit(Fail(AWhy, 'the key''s start is still there'));
    if (Pos(cKey, run.Outcome.Detail) > 0) or (Pos(cKey, sentence) > 0) then
      Exit(Fail(AWhy, 'the key is still there'));
    if Pos('***', sentence) = 0 then Exit(Fail(AWhy, 'nothing was masked'));
    if Pos('Incorrect API key', sentence) = 0 then Exit(Fail(AWhy, 'the service''s words are gone'));
    Result := True;
    AWhy := '';
  finally
    run.Free;
    srv.Free;
  end;
end;

function AiCheckRateLimit(out AWhy: string): Boolean;
const
  cBody = '{"type":"error","error":{"type":"rate_limit_error","message":"Number of requests has exceeded your rate limit"}}';
var
  srv: TTbFakeHttpServer;
  run: TTbAiRun;
  sentence: string;
begin
  Result := False;
  run := nil;
  srv := TTbFakeHttpServer.Create;
  try
    if not RunStatus(429, cBody, tafAnthropic, cFakeKey, run, AWhy, srv) then Exit;
    if run.Outcome.Kind <> aekRateLimit then Exit(Fail(AWhy, 'not a rate limit: ' + AiDescribe(run)));
    sentence := TbAiErrorSentence(run.Outcome, run.Profile);
    if Pos(rsTbAiRateLimit, sentence) <> 1 then Exit(Fail(AWhy, 'the sentence: ' + sentence));
    if Pos('(Number of requests has exceeded your rate limit)', sentence) = 0 then
      Exit(Fail(AWhy, 'the service''s words: ' + sentence));
    Result := True;
    AWhy := '';
  finally
    run.Free;
    srv.Free;
  end;
end;

function AiCheckNotFound(out AWhy: string): Boolean;
var
  srv: TTbFakeHttpServer;
  run: TTbAiRun;
  sentence: string;
begin
  Result := False;
  run := nil;
  srv := TTbFakeHttpServer.Create;
  try
    if not RunStatus(404, TbLoadFixture('ollama-404.json'), tafOpenAI, '', run, AWhy, srv) then Exit;
    if run.Outcome.Kind <> aekNotFound then Exit(Fail(AWhy, 'not "not found": ' + AiDescribe(run)));
    sentence := TbAiErrorSentence(run.Outcome, run.Profile);
    if Pos('model "qwen9" not found', sentence) = 0 then Exit(Fail(AWhy, 'the sentence: ' + sentence));
    Result := True;
    AWhy := '';
  finally
    run.Free;
    srv.Free;
  end;
end;

function AiCheckServerErrors(out AWhy: string): Boolean;
var
  srv: TTbFakeHttpServer;
  run: TTbAiRun;
  code, k: Integer;
begin
  Result := False;
  for k := 0 to 1 do
  begin
    if k = 0 then code := 500 else code := 529;
    run := nil;
    srv := TTbFakeHttpServer.Create;
    try
      if not RunStatus(code, '{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}',
         tafAnthropic, cFakeKey, run, AWhy, srv) then Exit;
      if run.Outcome.Kind <> aekServer then
        Exit(Fail(AWhy, Format('%d: not a server error: %s', [code, AiDescribe(run)])));
    finally
      run.Free;
      srv.Free;
    end;
  end;
  Result := True;
  AWhy := '';
end;

function AiCheckBroken(out AWhy: string): Boolean;
var
  srv: TTbFakeHttpServer;
  run: TTbAiRun;
  data: RawByteString;
  cut: Integer;
begin
  Result := False;
  run := nil;
  srv := TTbFakeHttpServer.Create;
  try
    data := TbLoadFixture('openai-ok.sse');
    cut := EventStartOf(data, ':root { --accent');
    if cut = 0 then Exit(Fail(AWhy, 'the sample has no :root event'));
    StreamPieces(srv, Copy(data, 1, cut - 1), [cut div 2], False);
    if not RunClient(srv, AiProfile(srv, tafOpenAI), cFakeKey, run, AWhy) then Exit;
    if run.Outcome.Kind <> aekBroken then Exit(Fail(AWhy, 'not broken: ' + AiDescribe(run)));
    if run.Outcome.Text <> 'Here is the theme, ' + cChinese + '.'#10'```tycss'#10 then
      Exit(Fail(AWhy, 'the half that came: ' + run.Outcome.Text));
    Result := True;
    AWhy := '';
  finally
    run.Free;
    srv.Free;
  end;
end;

function AiCheckNeverFinished(out AWhy: string): Boolean;
var
  srv: TTbFakeHttpServer;
  run: TTbAiRun;
  data: RawByteString;
  cut: Integer;
begin
  Result := False;
  run := nil;
  srv := TTbFakeHttpServer.Create;
  try
    data := TbLoadFixture('openai-ok.sse');
    cut := EventStartOf(data, '"finish_reason":"stop"');
    if cut = 0 then Exit(Fail(AWhy, 'the sample has no final chunk'));
    StreamPieces(srv, Copy(data, 1, cut - 1), [], True);    { a proper end of the body }
    if not RunClient(srv, AiProfile(srv, tafOpenAI), cFakeKey, run, AWhy) then Exit;
    if run.Outcome.Kind <> aekBroken then Exit(Fail(AWhy, 'taken as complete: ' + AiDescribe(run)));
    Result := True;
    AWhy := '';
  finally
    run.Free;
    srv.Free;
  end;
end;

function AiCheckTimeout(out AWhy: string): Boolean;
var
  srv: TTbFakeHttpServer;
  run: TTbAiRun;
  data: RawByteString;
  prof: TTbAiProfile;
  sentence: string;
begin
  Result := False;
  run := nil;
  srv := TTbFakeHttpServer.Create;
  try
    data := TbLoadFixture('openai-ok.sse');
    StreamPieces(srv, Copy(data, 1, EventStartOf(data, 'Here is the theme') - 1), [], False, True);
    prof := AiProfile(srv, tafOpenAI);
    prof.TimeoutSec := 1;
    if not RunClient(srv, prof, cFakeKey, run, AWhy) then Exit;
    if run.Outcome.Kind <> aekTimeout then Exit(Fail(AWhy, 'not a timeout: ' + AiDescribe(run)));
    sentence := TbAiErrorSentence(run.Outcome, prof);
    if Pos(Format(rsTbAiTimeout, ['127.0.0.1', 1]), sentence) <> 1 then
      Exit(Fail(AWhy, 'the sentence: ' + sentence));
    Result := True;
    AWhy := '';
  finally
    run.Free;
    srv.Free;
  end;
end;

function AiCheckStreamError(out AWhy: string): Boolean;
var
  srv: TTbFakeHttpServer;
  run: TTbAiRun;
  sentence: string;
begin
  Result := False;
  run := nil;
  srv := TTbFakeHttpServer.Create;
  try
    StreamPieces(srv, TbLoadFixture('anthropic-error.sse'), [], True);
    if not RunClient(srv, AiProfile(srv, tafAnthropic), cFakeKey, run, AWhy) then Exit;
    if run.Outcome.Kind <> aekServer then Exit(Fail(AWhy, 'not an error: ' + AiDescribe(run)));
    if run.Outcome.Status <> 200 then Exit(Fail(AWhy, Format('status %d', [run.Outcome.Status])));
    sentence := TbAiErrorSentence(run.Outcome, run.Profile);
    if sentence <> rsTbAiStreamError + ' ' + Format(rsTbAiServiceSays, ['Overloaded']) then
      Exit(Fail(AWhy, 'the sentence: ' + sentence));
    Result := True;
    AWhy := '';
  finally
    run.Free;
    srv.Free;
  end;
end;

function AiCheckTruncated(out AWhy: string): Boolean;
var
  srv: TTbFakeHttpServer;
  run: TTbAiRun;
begin
  Result := False;
  run := nil;
  srv := TTbFakeHttpServer.Create;
  try
    StreamPieces(srv, TbLoadFixture('openai-length.sse'), [], True);
    if not RunClient(srv, AiProfile(srv, tafOpenAI), cFakeKey, run, AWhy) then Exit;
    if run.Outcome.Kind <> aekTruncated then Exit(Fail(AWhy, 'OpenAI not cut off: ' + AiDescribe(run)));
    if run.Outcome.Text <> 'Here is the theme' then Exit(Fail(AWhy, 'OpenAI text: ' + run.Outcome.Text));
  finally
    FreeAndNil(run);
    srv.Free;
  end;
  srv := TTbFakeHttpServer.Create;
  try
    StreamPieces(srv, TbLoadFixture('anthropic-max-tokens.sse'), [], True);
    if not RunClient(srv, AiProfile(srv, tafAnthropic), cFakeKey, run, AWhy) then Exit;
    if run.Outcome.Kind <> aekTruncated then Exit(Fail(AWhy, 'Anthropic not cut off: ' + AiDescribe(run)));
    if run.Outcome.Text <> 'Here is' then Exit(Fail(AWhy, 'Anthropic text: ' + run.Outcome.Text));
    Result := True;
    AWhy := '';
  finally
    run.Free;
    srv.Free;
  end;
end;

function AiCheckRefused(out AWhy: string): Boolean;
var
  srv: TTbFakeHttpServer;
  run: TTbAiRun;
begin
  Result := False;
  run := nil;
  srv := TTbFakeHttpServer.Create;
  try
    StreamPieces(srv, TbLoadFixture('anthropic-refusal.sse'), [], True);
    if not RunClient(srv, AiProfile(srv, tafAnthropic), cFakeKey, run, AWhy) then Exit;
    if run.Outcome.Kind <> aekRefused then Exit(Fail(AWhy, 'not refused: ' + AiDescribe(run)));
    Result := True;
    AWhy := '';
  finally
    run.Free;
    srv.Free;
  end;
end;

function AiCheckNotStreamed(out AWhy: string): Boolean;
var
  srv: TTbFakeHttpServer;
  run: TTbAiRun;
begin
  Result := False;
  run := nil;
  srv := TTbFakeHttpServer.Create;
  try
    if not RunStatus(200, TbLoadFixture('openai-whole.json'), tafOpenAI, cFakeKey, run, AWhy, srv) then Exit;
    if run.Outcome.Kind <> aekNone then Exit(Fail(AWhy, 'refused a whole reply: ' + AiDescribe(run)));
    if run.Outcome.Text <> 'Done.'#10'```tycss'#10':root { --accent: #7C3AED; }'#10'```' then
      Exit(Fail(AWhy, 'the text: ' + run.Outcome.Text));
    if run.TextPieces <> 1 then Exit(Fail(AWhy, Format('%d text pieces (one expected)', [run.TextPieces])));
    Result := True;
    AWhy := '';
  finally
    run.Free;
    srv.Free;
  end;
end;

function AiCheckBadFormat(out AWhy: string): Boolean;
var
  srv: TTbFakeHttpServer;
  run: TTbAiRun;
  sentence: string;
begin
  Result := False;
  run := nil;
  srv := TTbFakeHttpServer.Create;
  try
    srv.Script([FakeSend(FakeHead(200, 'text/html', False, '<html>hello</html>'))]);
    if not RunClient(srv, AiProfile(srv, tafOpenAI), cFakeKey, run, AWhy) then Exit;
    if run.Outcome.Kind <> aekBadFormat then Exit(Fail(AWhy, 'not a bad format: ' + AiDescribe(run)));
    sentence := TbAiErrorSentence(run.Outcome, run.Profile);
    if Pos('(<html>hello', sentence) = 0 then Exit(Fail(AWhy, 'the sentence: ' + sentence));
    Result := True;
    AWhy := '';
  finally
    run.Free;
    srv.Free;
  end;
end;

function AiCheckCancel(out AWhy: string): Boolean;
var
  srv: TTbFakeHttpServer;
  run: TTbAiRun;
  data: RawByteString;
  prof: TTbAiProfile;
  t0, cancelAt: QWord;
begin
  Result := False;
  run := nil;
  srv := TTbFakeHttpServer.Create;
  try
    data := TbLoadFixture('openai-ok.sse');
    StreamPieces(srv, Copy(data, 1, EventStartOf(data, '```tycss') - 1), [], False, True);
    prof := AiProfile(srv, tafOpenAI);
    prof.TimeoutSec := 30;
    run := TTbAiRun.Create(prof, cFakeKey);
    run.Start;
    t0 := GetTickCount64;
    while (run.TextCount = 0) and (GetTickCount64 - t0 < 5000) and not run.Finished do
      CheckSynchronize(10);
    if run.TextCount = 0 then Exit(Fail(AWhy, 'no text before cancelling: ' + AiDescribe(run)));
    while GetTickCount64 - t0 < 300 do
      CheckSynchronize(10);
    cancelAt := GetTickCount64;
    run.Client.Cancel;
    if not run.WaitDone(10000) then Exit(Fail(AWhy, 'Cancel did not stop it in 10 s'));
    if run.Outcome.Kind <> aekCancelled then Exit(Fail(AWhy, 'not cancelled: ' + AiDescribe(run)));
    if GetTickCount64 - cancelAt > QWord(TbCancelGraceMs) then
      Exit(Fail(AWhy, Format('came back %d ms after Cancel', [GetTickCount64 - cancelAt])));
    if run.Outcome.Text <> 'Here is the theme, ' + cChinese + '.'#10 then
      Exit(Fail(AWhy, 'the text that came: ' + run.Outcome.Text));
    Result := True;
    AWhy := '';
  finally
    run.Free;
    srv.Free;
  end;
end;

function AiCheckNoKeyNoHeader(out AWhy: string): Boolean;
var
  srv: TTbFakeHttpServer;
  run: TTbAiRun;
  i: Integer;
begin
  Result := False;
  run := nil;
  srv := TTbFakeHttpServer.Create;
  try
    StreamPieces(srv, TbLoadFixture('openai-ok.sse'), [], True);
    if not RunClient(srv, AiProfile(srv, tafOpenAI), '', run, AWhy) then Exit;
    if run.Outcome.Kind <> aekNone then Exit(Fail(AWhy, 'failed: ' + AiDescribe(run)));
    for i := 0 to High(srv.LastRequest.Headers) do
      if Copy(srv.LastRequest.Headers[i], 1, 14) = 'authorization:' then
        Exit(Fail(AWhy, 'an Authorization header went out with no key'));
    Result := True;
    AWhy := '';
  finally
    run.Free;
    srv.Free;
  end;
end;

{ C18: a 301 / 302 / 307 / 308 from server A to server B is not followed -- B never sees a
  connection (it would get the key in a header) -- and the sentence names B's host but not
  the Location's query }
function AiCheckRedirects(out AWhy: string): Boolean;
const
  cCodes: array[0..3] of Integer = (301, 302, 307, 308);
var
  a, b: TTbFakeHttpServer;
  run: TTbAiRun;
  fmt: TTbAiFormat;
  loc, sentence: string;
  i: Integer;
  t0: QWord;
begin
  Result := False;
  for i := 0 to High(cCodes) do
  begin
    run := nil;
    a := TTbFakeHttpServer.Create;
    b := TTbFakeHttpServer.Create;
    try
      b.Script([FakeSend(FakeHead(200, 'text/event-stream', False, TbLoadFixture('openai-ok.sse')))]);
      if Odd(i) then fmt := tafAnthropic else fmt := tafOpenAI;
      loc := 'http://localhost:' + IntToStr(b.Port) + '/v1/chat/completions?token=QSECRET';
      a.Script([FakeSend('HTTP/1.1 ' + IntToStr(cCodes[i]) + ' Moved'#13#10'Location: ' + loc +
        #13#10'Content-Length: 0'#13#10'Connection: close'#13#10#13#10)]);
      if not RunClient(a, AiProfile(a, fmt), cFakeKey, run, AWhy) then Exit;
      { a follow would have connected by now; give a late one a moment anyway }
      t0 := GetTickCount64;
      while GetTickCount64 - t0 < 150 do
        CheckSynchronize(10);
      if (b.RequestCount <> 0) or (b.DoneCount <> 0) then
        Exit(Fail(AWhy, Format('%d: the redirect was followed (%d requests, %d connections at the target)',
          [cCodes[i], b.RequestCount, b.DoneCount])));
      if a.RequestCount <> 1 then
        Exit(Fail(AWhy, Format('%d: %d requests at the first server', [cCodes[i], a.RequestCount])));
      if run.Outcome.Kind <> aekRedirect then
        Exit(Fail(AWhy, Format('%d: not a redirect: %s', [cCodes[i], AiDescribe(run)])));
      if run.Outcome.Status <> cCodes[i] then
        Exit(Fail(AWhy, Format('%d: status %d', [cCodes[i], run.Outcome.Status])));
      sentence := TbAiErrorSentence(run.Outcome, run.Profile);
      if sentence <> Format(rsTbAiRedirect, [cCodes[i], 'localhost']) then
        Exit(Fail(AWhy, Format('%d: the sentence: %s', [cCodes[i], sentence])));
      if Pos('QSECRET', sentence) > 0 then
        Exit(Fail(AWhy, 'the Location''s query is in the sentence'));
    finally
      run.Free;
      a.Free;
      b.Free;
    end;
  end;
  Result := True;
  AWhy := '';
end;

{ ---- recording transports ---- }

function TTbRecordingTransport.Execute(const ARequest: TTbHttpRequest;
  AOnStatus: TTbHttpStatusEvent; AOnData: TTbHttpDataEvent): TTbHttpResult;
begin
  InterLockedIncrement(TbRecordedRequests);
  TbRecordedUrl := ARequest.Url;
  Result := Default(TTbHttpResult);
  Result.Error := hekCannotConnect;
end;

procedure TTbRecordingTransport.Cancel;
begin
end;

function MakeRecording(out AReason: string): TTbHttpTransport;
begin
  AReason := '';
  Result := TTbRecordingTransport.Create;
end;

procedure TbRecordTransports(AOn: Boolean);
begin
  TbRecordedRequests := 0;
  TbRecordedUrl := '';
  if AOn then
    TbTransportFactoryForTest := @MakeRecording
  else
    TbTransportFactoryForTest := nil;
end;

{ C19: a key is never sent over http:// to another computer -- the client refuses before a
  transport is even made; without a key (a local model elsewhere on the network), over
  https, or to this computer it goes. Recording transports: nothing reaches the network }
function AiCheckInsecureKey(out AWhy: string): Boolean;

  function TryRun(const AUrl, AKey: string; out ARun: TTbAiRun): Boolean;
  var
    prof: TTbAiProfile;
  begin
    prof := Default(TTbAiProfile);
    prof.Format := tafOpenAI;
    prof.BaseUrl := AUrl;
    prof.Model := 'm';
    prof.TimeoutSec := 5;
    TbRecordedRequests := 0;
    ARun := TTbAiRun.Create(prof, AKey);
    ARun.Start;
    Result := ARun.WaitDone(5000);
  end;

var
  run: TTbAiRun;
  sentence: string;
begin
  Result := False;
  run := nil;
  TbRecordTransports(True);
  try
    if not TryRun('http://192.0.2.10:8080/v1', cFakeKey, run) then Exit(Fail(AWhy, 'did not finish'));
    if run.Outcome.Kind <> aekInsecureKey then
      Exit(Fail(AWhy, 'a key over remote http: ' + AiDescribe(run)));
    if TbRecordedRequests <> 0 then Exit(Fail(AWhy, 'a transport was asked to send it'));
    sentence := TbAiErrorSentence(run.Outcome, run.Profile);
    if sentence <> Format(rsTbAiInsecureKey, ['192.0.2.10']) then
      Exit(Fail(AWhy, 'the sentence: ' + sentence));
    if Pos(cFakeKey, sentence) > 0 then Exit(Fail(AWhy, 'the key is in the sentence'));
    FreeAndNil(run);
    { the same with the upper-case scheme }
    if not TryRun('HTTP://192.0.2.10/v1', cFakeKey, run) then Exit(Fail(AWhy, 'did not finish'));
    if run.Outcome.Kind <> aekInsecureKey then
      Exit(Fail(AWhy, 'HTTP:// in capitals: ' + AiDescribe(run)));
    FreeAndNil(run);
    { allowed: no key; https; this computer by name, address and IPv6 }
    if not TryRun('http://192.0.2.10:11434/v1', '', run) then Exit(Fail(AWhy, 'did not finish'));
    if (run.Outcome.Kind <> aekCannotConnect) or (TbRecordedRequests <> 1) then
      Exit(Fail(AWhy, 'no key over remote http was not let through: ' + AiDescribe(run)));
    FreeAndNil(run);
    if not TryRun('https://192.0.2.10/v1', cFakeKey, run) then Exit(Fail(AWhy, 'did not finish'));
    if (run.Outcome.Kind <> aekCannotConnect) or (TbRecordedRequests <> 1) then
      Exit(Fail(AWhy, 'a key over https was not let through: ' + AiDescribe(run)));
    FreeAndNil(run);
    if not TryRun('http://localhost:11434/v1', cFakeKey, run) then Exit(Fail(AWhy, 'did not finish'));
    if (run.Outcome.Kind <> aekCannotConnect) or (TbRecordedRequests <> 1) then
      Exit(Fail(AWhy, 'a key to localhost was not let through: ' + AiDescribe(run)));
    FreeAndNil(run);
    if not TryRun('http://127.0.0.2:11434/v1', cFakeKey, run) then Exit(Fail(AWhy, 'did not finish'));
    if (run.Outcome.Kind <> aekCannotConnect) or (TbRecordedRequests <> 1) then
      Exit(Fail(AWhy, 'a key to 127.0.0.2 was not let through: ' + AiDescribe(run)));
    FreeAndNil(run);
    if not TryRun('http://[::1]:11434/v1', cFakeKey, run) then Exit(Fail(AWhy, 'did not finish'));
    if (run.Outcome.Kind <> aekCannotConnect) or (TbRecordedRequests <> 1) then
      Exit(Fail(AWhy, 'a key to [::1] was not let through: ' + AiDescribe(run)));
    Result := True;
    AWhy := '';
  finally
    run.Free;
    TbRecordTransports(False);
  end;
end;

{ ---- the K checks (settings and keys) ---- }

var
  GTempSeq: Integer = 0;

function TbAiTempDir: string;
begin
  Inc(GTempSeq);
  Result := IncludeTrailingPathDelimiter(GetTempDir(False)) +
    Format('tb3-ai-%d-%d', [GetProcessID, GTempSeq]) + PathDelim;
  ForceDirectories(Result);
end;

procedure TbAiRemoveDir(const ADir: string);
var
  sr: TSearchRec;
begin
  if FindFirst(ADir + '*', faAnyFile, sr) = 0 then
  begin
    repeat
      if (sr.Name <> '.') and (sr.Name <> '..') then
        SysUtils.DeleteFile(ADir + sr.Name);
    until FindNext(sr) <> 0;
    FindClose(sr);
  end;
  RemoveDir(ExcludeTrailingPathDelimiter(ADir));
end;

function ReadAll(const AFileName: string): RawByteString;
var
  fs: TFileStream;
begin
  Result := '';
  if not FileExists(AFileName) then Exit;
  fs := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, fs.Size);
    if fs.Size > 0 then
      fs.ReadBuffer(Result[1], fs.Size);
  finally
    fs.Free;
  end;
end;

function SameProfile(const A, B: TTbAiProfile): Boolean;
begin
  Result := (A.Id = B.Id) and (A.Name = B.Name) and (A.Format = B.Format) and
    (A.BaseUrl = B.BaseUrl) and (A.Model = B.Model) and (A.MaxOutput = B.MaxOutput) and
    (A.TimeoutSec = B.TimeoutSec);
end;

function SettingsCheckRoundTrip(out AWhy: string): Boolean;
var
  dir, ini, keys: string;
  a, b: TTbAiSettings;
  p1, p2, cur: TTbAiProfile;
begin
  Result := False;
  dir := TbAiTempDir;
  try
    TbAiFilesFor(dir + 'themebuilder.ini', ini, keys);
    a := TTbAiSettings.Create(ini, keys);
    b := TTbAiSettings.Create(ini, keys);
    try
      p1 := TbPresetProfile(tapAnthropic);
      p1.Name := 'Claude ' + cChinese;
      p1.MaxOutput := 12345;
      p2 := TbPresetProfile(tapOllama);
      p2.Name := 'Mine';
      p2.TimeoutSec := 77;
      a.Put(p1);
      a.Put(p2);
      a.CurrentId := p2.Id;
      if not a.Save then Exit(Fail(AWhy, 'Save said no'));
      b.Load;
      if b.Count <> 2 then Exit(Fail(AWhy, Format('%d profiles read back', [b.Count])));
      if not SameProfile(b.Profile(0), p1) then Exit(Fail(AWhy, 'the first profile changed'));
      if not SameProfile(b.Profile(1), p2) then Exit(Fail(AWhy, 'the second profile changed'));
      if not b.Current(cur) or (cur.Id <> p2.Id) then Exit(Fail(AWhy, 'the current profile changed'));
      Result := True;
      AWhy := '';
    finally
      a.Free;
      b.Free;
    end;
  finally
    TbAiRemoveDir(dir);
  end;
end;

{$IFDEF UNIX}
function FileMode(const AFileName: string): Integer;
var
  st: TStat;
begin
  if fpStat(PChar(AFileName), st) <> 0 then
    Exit(-1);
  Result := st.st_mode and &777;
end;

function SettingsCheckUnixKeyFile(out AWhy: string): Boolean;
const
  cKey = 'sk-test-ABCDEFGH12345678';
var
  dir, ini, keys: string;
  a, b: TTbAiSettings;
  p: TTbAiProfile;
begin
  Result := False;
  dir := TbAiTempDir;
  try
    TbAiFilesFor(dir + 'themebuilder.ini', ini, keys);
    if keys = '' then Exit(Fail(AWhy, 'no key file on Unix'));
    a := TTbAiSettings.Create(ini, keys);
    b := TTbAiSettings.Create(ini, keys);
    try
      p := TbPresetProfile(tapOpenAI);
      a.Put(p);
      a.SetKey(p.Id, cKey);
      if not a.Save then Exit(Fail(AWhy, 'Save said no'));
      if not FileExists(keys) then Exit(Fail(AWhy, 'no key file was written'));
      if FileMode(keys) <> &600 then Exit(Fail(AWhy, Format('the key file has mode %d (decimal; 384 = 0600)', [FileMode(keys)])));
      if (Pos(cKey, ReadAll(ini)) > 0) or (Pos('ABCDEFGH', ReadAll(ini)) > 0) then
        Exit(Fail(AWhy, 'the key is in the ini'));
      b.Load;
      if b.GetKey(p.Id) <> cKey then Exit(Fail(AWhy, 'the key did not come back'));
      Result := True;
      AWhy := '';
    finally
      a.Free;
      b.Free;
    end;
  finally
    TbAiRemoveDir(dir);
  end;
end;

{ K9: a key file left readable by others is set back to 0600 when it is read }
function SettingsCheckWideKeyFile(out AWhy: string): Boolean;
var
  dir, ini, keys: string;
  a: TTbAiSettings;
  p: TTbAiProfile;
  sl: TStringList;
begin
  Result := False;
  dir := TbAiTempDir;
  try
    TbAiFilesFor(dir + 'themebuilder.ini', ini, keys);
    a := TTbAiSettings.Create(ini, keys);
    try
      p := TbPresetProfile(tapOpenAI);
      a.Put(p);
      if not a.Save then Exit(Fail(AWhy, 'Save said no'));
    finally
      a.Free;
    end;
    sl := TStringList.Create;
    try
      sl.Add(p.Id + '=sk-test-0000');
      sl.SaveToFile(keys);
    finally
      sl.Free;
    end;
    fpChmod(PChar(keys), &644);
    if FileMode(keys) <> &644 then Exit(Fail(AWhy, 'could not make the file 0644 first'));
    a := TTbAiSettings.Create(ini, keys);
    try
      a.Load;
      if a.GetKey(p.Id) <> 'sk-test-0000' then Exit(Fail(AWhy, 'the key was not read'));
    finally
      a.Free;
    end;
    if FileMode(keys) <> &600 then Exit(Fail(AWhy, Format('still mode %d (decimal; 384 = 0600) after reading', [FileMode(keys)])));
    Result := True;
    AWhy := '';
  finally
    TbAiRemoveDir(dir);
  end;
end;

{ K10: a new private file is 0600 under the usual umask 022 }
function SettingsCheckPrivateFile(out AWhy: string): Boolean;
var
  dir: string;
begin
  Result := False;
  dir := TbAiTempDir;
  try
    fpUmask(&022);
    if not TbWritePrivateFile(dir + 'p.keys', 'x=y'#10) then Exit(Fail(AWhy, 'not written'));
    if FileMode(dir + 'p.keys') <> &600 then
      Exit(Fail(AWhy, Format('created with mode %d (decimal; 384 = 0600)', [FileMode(dir + 'p.keys')])));
    if ReadAll(dir + 'p.keys') <> 'x=y'#10 then Exit(Fail(AWhy, 'the bytes changed'));
    Result := True;
    AWhy := '';
  finally
    TbAiRemoveDir(dir);
  end;
end;
{$ENDIF}

end.
