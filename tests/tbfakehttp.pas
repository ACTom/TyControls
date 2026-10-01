unit tbfakehttp;
{ A small HTTP server for the AI tests: it answers each connection from a script -- send
  these bytes, sleep, close, hold the connection open until the client goes or the server
  stops -- so the real transports (WinHTTP, libcurl) can be driven through a streamed
  reply, a reply cut off half way, a stalled one, a refused key.

  Not fcl-web's fphttpserver: its response goes out in one SendContent, and "send a chunk,
  sleep, send half an event, drop the line" needs the socket itself. ssockets would do, but
  the real port and stopping it cleanly need wrapping again; this is about as long.

  It binds 127.0.0.1 only, port 0 (the system picks a free one): binding every address
  makes Windows' firewall ask the user on their desktop. One thread takes the connections
  one at a time. Every response carries "Connection: close" (FakeHead), so one request is
  one connection and the scripts line up with the requests.

  RTL / FCL only -- the WSL console program (tools/themebuilder-curl-wsl) uses it too. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, SyncObjs, sockets;

type
  TTbFakeStepKind = (fskSend, fskSleep, fskClose, fskHold);
  TTbFakeStep = record
    Kind: TTbFakeStepKind;
    Data: RawByteString;
    Ms: Integer;
  end;
  TTbFakeSteps = array of TTbFakeStep;

  TTbFakeRequest = record
    Method, Path: string;
    Headers: TStringArray;        { 'name: value' as received; name lower case }
    Body: RawByteString;
  end;

  TTbFakeHttpServer = class
  private
    FListen: LongInt;
    FPort: Word;
    FThread: TThread;
    FLock: TCriticalSection;
    FWake: TEvent;
    FStopping: Boolean;
    FDefault: TTbFakeSteps;
    FQueue: array of TTbFakeSteps;
    FRequests: array of TTbFakeRequest;
    FClosedByPeer: Integer;
    FDone: Integer;
    function Stopping: Boolean;
    function NextScript: TTbFakeSteps;
    procedure HandleConnection(ASock: LongInt);
  public
    constructor Create;                       { binds 127.0.0.1:0, starts listening }
    destructor Destroy; override;             { stops: wakes a Hold, wakes accept, joins }
    procedure Serve;                          { the server thread's body }
    { the steps for the next connections, in order; the last script repeats }
    procedure Script(const ASteps: array of TTbFakeStep);
    procedure Queue(const ASteps: array of TTbFakeStep);   { one more connection's script }
    function Url(const APath: string): string;             { 'http://127.0.0.1:<port>' + APath }
    function RequestCount: Integer;
    function LastRequest: TTbFakeRequest;
    function HeaderValue(const AName: string): string;     { of the last request; '' none }
    { connections whose Hold ended because the client went away }
    function ClosedByPeer: Integer;
    { connections the server has finished with (its script ran out or the client went) }
    function DoneCount: Integer;
    property Port: Word read FPort;
  end;

function FakeSend(const AData: RawByteString): TTbFakeStep;
function FakeSleep(AMs: Integer): TTbFakeStep;
function FakeClose: TTbFakeStep;
function FakeHold: TTbFakeStep;
{ 'HTTP/1.1 <code> <reason>'#13#10 + headers + blank line; AChunked adds Transfer-Encoding,
  otherwise Content-Length of ABody (and ABody is appended) }
function FakeHead(ACode: Integer; const AContentType: string; AChunked: Boolean;
  const ABody: RawByteString = ''): RawByteString;
function FakeChunk(const AData: RawByteString): RawByteString;   { hex length CRLF data CRLF }
function FakeLastChunk: RawByteString;                            { '0'#13#10#13#10 }
{ a port nothing listens on: bound, read, closed }
function FakeDeadPort: Word;

implementation

uses
  {$IFDEF MSWINDOWS} winsock2 {$ELSE} BaseUnix {$ENDIF};

const
  {$IFDEF LINUX}
  cSendFlags = MSG_NOSIGNAL;      { a client that went away must not kill the process }
  {$ELSE}
  cSendFlags = 0;
  {$ENDIF}
  cMaxHead = 65536;

type
  TTbFakeServerThread = class(TThread)
  private
    FOwner: TTbFakeHttpServer;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TTbFakeHttpServer);
  end;

{ >0 readable, 0 timed out, <0 error }
function WaitReadable(ASock: LongInt; AMs: Integer): Integer;
{$IFDEF MSWINDOWS}
var
  fds: TFDSet;
  tv: TTimeVal;
begin
  fds.fd_count := 1;
  fds.fd_array[0] := TSocket(ASock);
  tv.tv_sec := AMs div 1000;
  tv.tv_usec := (AMs mod 1000) * 1000;
  Result := winsock2.select(0, @fds, nil, nil, @tv);
end;
{$ELSE}
var
  fds: BaseUnix.TFDSet;
begin
  fpFD_ZERO(fds);
  fpFD_SET(ASock, fds);
  Result := fpSelect(ASock + 1, @fds, nil, nil, AMs);
end;
{$ENDIF}

function LoopbackAddr(APort: Word): TInetSockAddr;
begin
  Result := Default(TInetSockAddr);
  Result.sin_family := AF_INET;
  Result.sin_port := htons(APort);
  Result.sin_addr := StrToNetAddr('127.0.0.1');
end;

function SendAll(ASock: LongInt; const AData: RawByteString): Boolean;
var
  sent, n: Integer;
begin
  sent := 0;
  while sent < Length(AData) do
  begin
    n := fpSend(ASock, @AData[sent + 1], Length(AData) - sent, cSendFlags);
    if n <= 0 then
      Exit(False);
    Inc(sent, n);
  end;
  Result := True;
end;

function FakeSend(const AData: RawByteString): TTbFakeStep;
begin
  Result := Default(TTbFakeStep);
  Result.Kind := fskSend;
  Result.Data := AData;
end;

function FakeSleep(AMs: Integer): TTbFakeStep;
begin
  Result := Default(TTbFakeStep);
  Result.Kind := fskSleep;
  Result.Ms := AMs;
end;

function FakeClose: TTbFakeStep;
begin
  Result := Default(TTbFakeStep);
  Result.Kind := fskClose;
end;

function FakeHold: TTbFakeStep;
begin
  Result := Default(TTbFakeStep);
  Result.Kind := fskHold;
end;

function ReasonOf(ACode: Integer): string;
begin
  case ACode of
    200: Result := 'OK';
    400: Result := 'Bad Request';
    401: Result := 'Unauthorized';
    403: Result := 'Forbidden';
    404: Result := 'Not Found';
    429: Result := 'Too Many Requests';
    500: Result := 'Internal Server Error';
    529: Result := 'Overloaded';
  else
    Result := 'Status';
  end;
end;

function FakeHead(ACode: Integer; const AContentType: string; AChunked: Boolean;
  const ABody: RawByteString): RawByteString;
begin
  Result := 'HTTP/1.1 ' + IntToStr(ACode) + ' ' + ReasonOf(ACode) + #13#10;
  if AContentType <> '' then
    Result := Result + 'Content-Type: ' + AContentType + #13#10;
  if AChunked then
    Result := Result + 'Transfer-Encoding: chunked'#13#10
  else
    Result := Result + 'Content-Length: ' + IntToStr(Length(ABody)) + #13#10;
  Result := Result + 'Connection: close'#13#10#13#10;
  if not AChunked then
    Result := Result + ABody;
end;

function FakeChunk(const AData: RawByteString): RawByteString;
begin
  Result := LowerCase(IntToHex(Length(AData), 1)) + #13#10 + AData + #13#10;
end;

function FakeLastChunk: RawByteString;
begin
  Result := '0'#13#10#13#10;
end;

function FakeDeadPort: Word;
var
  s: LongInt;
  addr: TInetSockAddr;
  len: TSockLen;
begin
  Result := 0;
  s := fpSocket(AF_INET, SOCK_STREAM, 0);
  if s < 0 then Exit;
  try
    addr := LoopbackAddr(0);
    if fpBind(s, @addr, SizeOf(addr)) <> 0 then Exit;
    len := SizeOf(addr);
    if fpGetSockName(s, @addr, @len) <> 0 then Exit;
    Result := NToHs(addr.sin_port);
  finally
    CloseSocket(s);
  end;
end;

{ ---- the thread ---- }

constructor TTbFakeServerThread.Create(AOwner: TTbFakeHttpServer);
begin
  FOwner := AOwner;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TTbFakeServerThread.Execute;
begin
  FOwner.Serve;
end;

{ ---- the server ---- }

constructor TTbFakeHttpServer.Create;
var
  addr: TInetSockAddr;
  len: TSockLen;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FWake := TEvent.Create(nil, True, False, '');
  FListen := fpSocket(AF_INET, SOCK_STREAM, 0);
  if FListen < 0 then
    raise Exception.Create('fake server: no socket');
  addr := LoopbackAddr(0);
  if fpBind(FListen, @addr, SizeOf(addr)) <> 0 then
    raise Exception.Create('fake server: cannot bind 127.0.0.1');
  if fpListen(FListen, 8) <> 0 then
    raise Exception.Create('fake server: cannot listen');
  len := SizeOf(addr);
  fpGetSockName(FListen, @addr, @len);
  FPort := NToHs(addr.sin_port);
  FThread := TTbFakeServerThread.Create(Self);
end;

destructor TTbFakeHttpServer.Destroy;
var
  s: LongInt;
  addr: TInetSockAddr;
begin
  FLock.Enter;
  FStopping := True;
  FLock.Leave;
  FWake.SetEvent;
  if FThread <> nil then
  begin
    { a blocked accept wakes up when someone connects }
    s := fpSocket(AF_INET, SOCK_STREAM, 0);
    if s >= 0 then
    begin
      addr := LoopbackAddr(FPort);
      fpConnect(s, @addr, SizeOf(addr));
      CloseSocket(s);
    end;
    FThread.WaitFor;
    FThread.Free;
  end;
  CloseSocket(FListen);
  FWake.Free;
  FLock.Free;
  inherited Destroy;
end;

function TTbFakeHttpServer.Stopping: Boolean;
begin
  FLock.Enter;
  try
    Result := FStopping;
  finally
    FLock.Leave;
  end;
end;

procedure TTbFakeHttpServer.Script(const ASteps: array of TTbFakeStep);
var
  i: Integer;
begin
  FLock.Enter;
  try
    SetLength(FDefault, Length(ASteps));
    for i := 0 to High(ASteps) do
      FDefault[i] := ASteps[i];
  finally
    FLock.Leave;
  end;
end;

procedure TTbFakeHttpServer.Queue(const ASteps: array of TTbFakeStep);
var
  i, n: Integer;
begin
  FLock.Enter;
  try
    n := Length(FQueue);
    SetLength(FQueue, n + 1);
    SetLength(FQueue[n], Length(ASteps));
    for i := 0 to High(ASteps) do
      FQueue[n][i] := ASteps[i];
  finally
    FLock.Leave;
  end;
end;

function TTbFakeHttpServer.NextScript: TTbFakeSteps;
var
  i: Integer;
begin
  FLock.Enter;
  try
    if Length(FQueue) > 0 then
    begin
      Result := FQueue[0];
      for i := 1 to High(FQueue) do
        FQueue[i - 1] := FQueue[i];
      SetLength(FQueue, Length(FQueue) - 1);
    end
    else
      Result := Copy(FDefault);
  finally
    FLock.Leave;
  end;
end;

function TTbFakeHttpServer.Url(const APath: string): string;
begin
  Result := 'http://127.0.0.1:' + IntToStr(FPort) + APath;
end;

function TTbFakeHttpServer.RequestCount: Integer;
begin
  FLock.Enter;
  try
    Result := Length(FRequests);
  finally
    FLock.Leave;
  end;
end;

function TTbFakeHttpServer.LastRequest: TTbFakeRequest;
begin
  FLock.Enter;
  try
    if Length(FRequests) = 0 then
      Result := Default(TTbFakeRequest)
    else
      Result := FRequests[High(FRequests)];
  finally
    FLock.Leave;
  end;
end;

function TTbFakeHttpServer.HeaderValue(const AName: string): string;
var
  r: TTbFakeRequest;
  i: Integer;
  prefix: string;
begin
  Result := '';
  r := LastRequest;
  prefix := LowerCase(AName) + ':';
  for i := 0 to High(r.Headers) do
    if Copy(r.Headers[i], 1, Length(prefix)) = prefix then
      Exit(Trim(Copy(r.Headers[i], Length(prefix) + 1, MaxInt)));
end;

function TTbFakeHttpServer.ClosedByPeer: Integer;
begin
  FLock.Enter;
  try
    Result := FClosedByPeer;
  finally
    FLock.Leave;
  end;
end;

function TTbFakeHttpServer.DoneCount: Integer;
begin
  FLock.Enter;
  try
    Result := FDone;
  finally
    FLock.Leave;
  end;
end;

procedure TTbFakeHttpServer.Serve;
var
  c: LongInt;
begin
  while not Stopping do
  begin
    c := fpAccept(FListen, nil, nil);
    if c < 0 then
    begin
      if Stopping then Break;
      Sleep(5);
      Continue;
    end;
    if Stopping then
    begin
      CloseSocket(c);
      Break;
    end;
    try
      HandleConnection(c);
    except
      { a script that went wrong must not take the thread down }
    end;
    CloseSocket(c);
    FLock.Enter;
    Inc(FDone);
    FLock.Leave;
  end;
end;

procedure TTbFakeHttpServer.HandleConnection(ASock: LongInt);
var
  buf: array[0..4095] of Char;
  data, chunk, head, line, name, value: RawByteString;
  req: TTbFakeRequest;
  steps: TTbFakeSteps;
  lines: TStringList;
  p, n, i, want: Integer;
  peerGone: Boolean;

  function ReadMore: Boolean;
  var
    r: Integer;
  begin
    repeat
      if Stopping then Exit(False);
      r := WaitReadable(ASock, 50);
    until r <> 0;
    if r < 0 then Exit(False);
    n := fpRecv(ASock, @buf[0], SizeOf(buf), 0);
    if n <= 0 then Exit(False);
    SetString(chunk, PChar(@buf[0]), n);
    data := data + chunk;
    Result := True;
  end;

begin
  data := '';
  req := Default(TTbFakeRequest);
  { the head }
  repeat
    p := Pos(#13#10#13#10, data);
    if p > 0 then Break;
    if Length(data) > cMaxHead then Exit;
    if not ReadMore then Exit;
  until False;
  head := Copy(data, 1, p - 1);
  Delete(data, 1, p + 3);
  lines := TStringList.Create;
  try
    lines.Text := StringReplace(head, #13#10, #10, [rfReplaceAll]);
    if lines.Count = 0 then Exit;
    line := lines[0];
    p := Pos(' ', line);
    req.Method := Copy(line, 1, p - 1);
    line := Copy(line, p + 1, MaxInt);
    p := Pos(' ', line);
    if p > 0 then
      req.Path := Copy(line, 1, p - 1)
    else
      req.Path := line;
    SetLength(req.Headers, lines.Count - 1);
    for i := 1 to lines.Count - 1 do
    begin
      p := Pos(':', lines[i]);
      if p > 0 then
      begin
        name := LowerCase(Trim(Copy(lines[i], 1, p - 1)));
        value := Trim(Copy(lines[i], p + 1, MaxInt));
      end
      else
      begin
        name := LowerCase(Trim(lines[i]));
        value := '';
      end;
      req.Headers[i - 1] := name + ': ' + value;
    end;
  finally
    lines.Free;
  end;
  want := 0;
  for i := 0 to High(req.Headers) do
  begin
    if Copy(req.Headers[i], 1, 15) = 'content-length:' then
      want := StrToIntDef(Trim(Copy(req.Headers[i], 16, MaxInt)), 0)
    else if (Copy(req.Headers[i], 1, 7) = 'expect:') and
       (Pos('100-continue', LowerCase(req.Headers[i])) > 0) and (Length(data) = 0) then
      SendAll(ASock, 'HTTP/1.1 100 Continue'#13#10#13#10);
  end;
  while Length(data) < want do
    if not ReadMore then Break;
  req.Body := Copy(data, 1, want);
  FLock.Enter;
  try
    SetLength(FRequests, Length(FRequests) + 1);
    FRequests[High(FRequests)] := req;
  finally
    FLock.Leave;
  end;

  steps := NextScript;
  for i := 0 to High(steps) do
  begin
    if Stopping then Exit;
    case steps[i].Kind of
      fskSend:
        if not SendAll(ASock, steps[i].Data) then
          Exit;
      fskSleep:
        if FWake.WaitFor(steps[i].Ms) = wrSignaled then
          Exit;
      fskClose:
        Exit;
      fskHold:
        begin
          peerGone := False;
          while not Stopping do
          begin
            n := WaitReadable(ASock, 50);
            if n = 0 then Continue;
            if n < 0 then
            begin
              peerGone := True;
              Break;
            end;
            if fpRecv(ASock, @buf[0], SizeOf(buf), 0) <= 0 then
            begin
              peerGone := True;
              Break;
            end;
          end;
          if peerGone then
          begin
            FLock.Enter;
            Inc(FClosedByPeer);
            FLock.Leave;
          end;
          Exit;
        end;
    end;
  end;
end;

end.
