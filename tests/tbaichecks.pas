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
  Classes, SysUtils, SyncObjs, tbhttp, tbfakehttp;

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

implementation

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

end.
