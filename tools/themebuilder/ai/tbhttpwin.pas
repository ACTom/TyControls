unit tbhttpwin;
{ The HTTP transport on Windows: WinHTTP, synchronous, on the caller's (worker) thread.

  Declared here rather than taken from FPC's winhttp unit: that H2Pas binding names
  WinHttpSetTimeouts "WinHttpSetTimes", which winhttp.dll does not export, and has the error
  constants' names mangled (ERROR_WINHTTP_TIME for ERROR_WINHTTP_TIMEOUT). Ten functions and
  a few constants are all this needs.

  The proxy is the system's: WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY (Windows 8.1 and later:
  the user's settings and PAC), falling back to WINHTTP_ACCESS_TYPE_DEFAULT_PROXY (netsh
  winhttp) on older systems where the automatic one is refused. A loopback address (a
  local model, the tests' server) never goes through a proxy.

  Timeouts: resolving and connecting get the connect timeout; sending and every receive
  (the headers, each QueryDataAvailable, each ReadData) the idle timeout -- WinHTTP applies
  the receive timeout to each blocking call, so "no byte for this long" is what it means.

  Redirects: the request handle's redirect policy is "never" (WinHTTP's default follows a
  redirect to any host, our headers -- the key -- included); a 3xx comes back as the status
  with its Location header.

  Cancel closes the request handle from the other thread; the blocked call then fails
  (12017 or 6) and Execute reports hekCancelled. The handle is closed once only: under a
  lock, with a flag, whoever comes first. }
{$mode objfpc}{$H+}
interface

{$IFDEF MSWINDOWS}
uses
  Windows, Classes, SysUtils, SyncObjs, tbhttp;

type
  HINTERNET = Pointer;

  TTbWinHttpTransport = class(TTbHttpTransport)
  private
    FLock: TCriticalSection;
    FRequest: HINTERNET;
    FCancelled: Boolean;
    FRequestClosed: Boolean;
    FStatus: DWORD;
    function IsCancelled: Boolean;
    function OpenRequest(AConnect: HINTERNET; const APath: UnicodeString; AFlags: DWORD): Boolean;
    procedure CloseRequest;
  public
    constructor Create;
    destructor Destroy; override;
    function Execute(const ARequest: TTbHttpRequest; AOnStatus: TTbHttpStatusEvent;
      AOnData: TTbHttpDataEvent): TTbHttpResult; override;
    procedure Cancel; override;
  end;

function TbWinHttpErrorKind(ACode: DWORD): TTbHttpErrorKind;
{$ENDIF}

implementation

{$IFDEF MSWINDOWS}

const
  cWinHttp = 'winhttp.dll';
  WINHTTP_ACCESS_TYPE_DEFAULT_PROXY = 0;
  WINHTTP_ACCESS_TYPE_NO_PROXY = 1;
  WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY = 4;   { Windows 8.1 and later }
  WINHTTP_FLAG_SECURE = $00800000;
  WINHTTP_QUERY_STATUS_CODE = 19;
  WINHTTP_QUERY_LOCATION = 33;
  WINHTTP_QUERY_FLAG_NUMBER = $20000000;
  WINHTTP_OPTION_REDIRECT_POLICY = 88;
  WINHTTP_OPTION_REDIRECT_POLICY_NEVER = 0;
  WINHTTP_ADDREQ_FLAG_ADD = $20000000;
  WINHTTP_ADDREQ_FLAG_REPLACE = $80000000;
  ERROR_WINHTTP_TIMEOUT = 12002;
  ERROR_WINHTTP_INVALID_URL = 12005;
  ERROR_WINHTTP_UNRECOGNIZED_SCHEME = 12006;
  ERROR_WINHTTP_NAME_NOT_RESOLVED = 12007;
  ERROR_WINHTTP_OPERATION_CANCELLED = 12017;
  ERROR_WINHTTP_CANNOT_CONNECT = 12029;
  ERROR_WINHTTP_CONNECTION_ERROR = 12030;
  ERROR_WINHTTP_SECURE_CERT_DATE_INVALID = 12037;
  ERROR_WINHTTP_SECURE_CERT_REV_FAILED = 12057;
  ERROR_WINHTTP_INVALID_SERVER_RESPONSE = 12152;
  ERROR_WINHTTP_SECURE_INVALID_CA = 12045;
  ERROR_WINHTTP_SECURE_CHANNEL_ERROR = 12157;
  ERROR_WINHTTP_SECURE_INVALID_CERT = 12169;
  ERROR_WINHTTP_SECURE_FAILURE = 12175;

function WinHttpOpen(pszAgent: PWideChar; dwAccessType: DWORD; pszProxy, pszProxyBypass: PWideChar;
  dwFlags: DWORD): HINTERNET; stdcall; external cWinHttp;
function WinHttpSetTimeouts(h: HINTERNET; nResolve, nConnect, nSend, nReceive: Integer): BOOL;
  stdcall; external cWinHttp;
function WinHttpConnect(h: HINTERNET; pswzServerName: PWideChar; nServerPort: Word;
  dwReserved: DWORD): HINTERNET; stdcall; external cWinHttp;
function WinHttpOpenRequest(h: HINTERNET; pwszVerb, pwszObjectName, pwszVersion,
  pwszReferrer: PWideChar; ppwszAcceptTypes: Pointer; dwFlags: DWORD): HINTERNET;
  stdcall; external cWinHttp;
function WinHttpAddRequestHeaders(h: HINTERNET; lpszHeaders: PWideChar; dwHeadersLength,
  dwModifiers: DWORD): BOOL; stdcall; external cWinHttp;
function WinHttpSendRequest(h: HINTERNET; lpszHeaders: PWideChar; dwHeadersLength: DWORD;
  lpOptional: Pointer; dwOptionalLength, dwTotalLength: DWORD; dwContext: PtrUInt): BOOL;
  stdcall; external cWinHttp;
function WinHttpReceiveResponse(h: HINTERNET; lpReserved: Pointer): BOOL; stdcall; external cWinHttp;
function WinHttpQueryHeaders(h: HINTERNET; dwInfoLevel: DWORD; pwszName: PWideChar;
  lpBuffer: Pointer; lpdwBufferLength, lpdwIndex: PDWORD): BOOL; stdcall; external cWinHttp;
function WinHttpQueryDataAvailable(h: HINTERNET; lpdwNumberOfBytesAvailable: PDWORD): BOOL;
  stdcall; external cWinHttp;
function WinHttpReadData(h: HINTERNET; lpBuffer: Pointer; dwNumberOfBytesToRead: DWORD;
  lpdwNumberOfBytesRead: PDWORD): BOOL; stdcall; external cWinHttp;
function WinHttpCloseHandle(h: HINTERNET): BOOL; stdcall; external cWinHttp;
function WinHttpSetOption(h: HINTERNET; dwOption: DWORD; lpBuffer: Pointer;
  dwBufferLength: DWORD): BOOL; stdcall; external cWinHttp;

{ the Location header of the response; '' when there is none }
function QueryLocation(ARequest: HINTERNET): string;
var
  size: DWORD;
  buf: UnicodeString;
begin
  Result := '';
  size := 0;
  WinHttpQueryHeaders(ARequest, WINHTTP_QUERY_LOCATION, nil, nil, @size, nil);
  if size < SizeOf(WideChar) then Exit;
  SetLength(buf, size div SizeOf(WideChar));
  if not WinHttpQueryHeaders(ARequest, WINHTTP_QUERY_LOCATION, nil, PWideChar(buf), @size, nil) then
    Exit;
  SetLength(buf, size div SizeOf(WideChar));
  Result := UTF8Encode(buf);
end;

function TbWinHttpErrorKind(ACode: DWORD): TTbHttpErrorKind;
begin
  case ACode of
    ERROR_WINHTTP_TIMEOUT: Result := hekTimeout;
    ERROR_WINHTTP_INVALID_URL, ERROR_WINHTTP_UNRECOGNIZED_SCHEME: Result := hekBadUrl;
    ERROR_WINHTTP_NAME_NOT_RESOLVED: Result := hekNameNotResolved;
    ERROR_WINHTTP_OPERATION_CANCELLED: Result := hekCancelled;
    ERROR_WINHTTP_CANNOT_CONNECT: Result := hekCannotConnect;
    ERROR_WINHTTP_CONNECTION_ERROR, ERROR_WINHTTP_INVALID_SERVER_RESPONSE: Result := hekBroken;
    ERROR_WINHTTP_SECURE_CERT_DATE_INVALID..ERROR_WINHTTP_SECURE_INVALID_CA,
    ERROR_WINHTTP_SECURE_CERT_REV_FAILED,
    ERROR_WINHTTP_SECURE_CHANNEL_ERROR, ERROR_WINHTTP_SECURE_INVALID_CERT,
    ERROR_WINHTTP_SECURE_FAILURE: Result := hekTls;
  else
    Result := hekOther;
  end;
end;

{ 'A: b'#13#10'C: d' }
function JoinHeaders(const AHeaders: TStringArray): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(AHeaders) do
  begin
    if Result <> '' then
      Result := Result + #13#10;
    Result := Result + AHeaders[i];
  end;
end;

constructor TTbWinHttpTransport.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
end;

destructor TTbWinHttpTransport.Destroy;
begin
  CloseRequest;
  FLock.Free;
  inherited Destroy;
end;

function TTbWinHttpTransport.IsCancelled: Boolean;
begin
  FLock.Enter;
  try
    Result := FCancelled;
  finally
    FLock.Leave;
  end;
end;

function TTbWinHttpTransport.OpenRequest(AConnect: HINTERNET; const APath: UnicodeString;
  AFlags: DWORD): Boolean;
var
  h: HINTERNET;
begin
  h := WinHttpOpenRequest(AConnect, PWideChar(UnicodeString('POST')), PWideChar(APath), nil,
    nil, nil, AFlags);
  if h = nil then
    Exit(False);
  FLock.Enter;
  try
    if FCancelled then
    begin
      { cancelled before there was a handle to close: close this one now }
      WinHttpCloseHandle(h);
      FRequestClosed := True;
      FRequest := nil;
      Exit(False);
    end;
    FRequest := h;
    FRequestClosed := False;
  finally
    FLock.Leave;
  end;
  Result := True;
end;

procedure TTbWinHttpTransport.CloseRequest;
begin
  FLock.Enter;
  try
    if (FRequest <> nil) and not FRequestClosed then
    begin
      WinHttpCloseHandle(FRequest);
      FRequestClosed := True;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TTbWinHttpTransport.Cancel;
begin
  FLock.Enter;
  try
    FCancelled := True;
    if (FRequest <> nil) and not FRequestClosed then
    begin
      { a blocked WinHttpReceiveResponse / QueryDataAvailable / ReadData fails at once }
      WinHttpCloseHandle(FRequest);
      FRequestClosed := True;
    end;
  finally
    FLock.Leave;
  end;
end;

function TTbWinHttpTransport.Execute(const ARequest: TTbHttpRequest;
  AOnStatus: TTbHttpStatusEvent; AOnData: TTbHttpDataEvent): TTbHttpResult;
var
  url: TTbUrlParts;
  session, conn: HINTERNET;
  access, flags, status, size, avail, got, policy: DWORD;
  buf: RawByteString;
  headers: UnicodeString;
  location: string;

  function Fail(AKind: TTbHttpErrorKind): TTbHttpResult;
  var
    code: DWORD;
  begin
    code := GetLastError;
    Result := Default(TTbHttpResult);
    Result.Status := FStatus;        { 0 until the headers came; kept after (a broken stream) }
    if IsCancelled then
      Result.Error := hekCancelled
    else if AKind <> hekOther then
      Result.Error := AKind
    else
      Result.Error := TbWinHttpErrorKind(code);
    if (AKind = hekBadUrl) or (AKind = hekCancelled) then
      Result.Detail := ''
    else
      Result.Detail := Format('WinHTTP %d', [code]);
  end;

begin
  Result := Default(TTbHttpResult);
  FStatus := 0;
  location := '';
  if not TbSplitUrl(ARequest.Url, url) then
    Exit(Fail(hekBadUrl));
  if IsCancelled then
    Exit(Fail(hekCancelled));
  if TbIsLoopbackHost(url.Host) then
    access := WINHTTP_ACCESS_TYPE_NO_PROXY
  else
    access := WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY;
  session := WinHttpOpen(PWideChar(UnicodeString(TbUserAgent)), access, nil, nil, 0);
  if (session = nil) and (access = WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY) then
    { before Windows 8.1: the proxy netsh winhttp configured }
    session := WinHttpOpen(PWideChar(UnicodeString(TbUserAgent)),
      WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, nil, nil, 0);
  if session = nil then
    Exit(Fail(hekOther));
  conn := nil;
  try
    WinHttpSetTimeouts(session, TbConnectTimeoutMs(ARequest), TbConnectTimeoutMs(ARequest),
      TbIdleTimeoutMs(ARequest), TbIdleTimeoutMs(ARequest));
    conn := WinHttpConnect(session, PWideChar(UTF8Decode(url.Host)), url.Port, 0);
    if conn = nil then
      Exit(Fail(hekOther));
    if url.Secure then flags := WINHTTP_FLAG_SECURE else flags := 0;
    if not OpenRequest(conn, UTF8Decode(url.Path), flags) then   { sets FRequest under FLock }
      Exit(Fail(hekOther));
    { never follow a redirect: WinHTTP's default policy follows one to another host with
      every header we added -- the key among them. Not sent at all when this is refused. }
    policy := WINHTTP_OPTION_REDIRECT_POLICY_NEVER;
    if not WinHttpSetOption(FRequest, WINHTTP_OPTION_REDIRECT_POLICY, @policy, SizeOf(policy)) then
      Exit(Fail(hekOther));
    headers := UTF8Decode(JoinHeaders(ARequest.Headers));
    if (headers <> '') and not WinHttpAddRequestHeaders(FRequest, PWideChar(headers),
       DWORD(-1), WINHTTP_ADDREQ_FLAG_ADD or WINHTTP_ADDREQ_FLAG_REPLACE) then
      Exit(Fail(hekOther));
    if not WinHttpSendRequest(FRequest, nil, 0, PAnsiChar(ARequest.Body),
       Length(ARequest.Body), Length(ARequest.Body), 0) then
      Exit(Fail(hekOther));
    if not WinHttpReceiveResponse(FRequest, nil) then
      Exit(Fail(hekOther));
    size := SizeOf(status);
    status := 0;
    if not WinHttpQueryHeaders(FRequest, WINHTTP_QUERY_STATUS_CODE or WINHTTP_QUERY_FLAG_NUMBER,
       nil, @status, @size, nil) then
      Exit(Fail(hekOther));
    FStatus := status;
    if (status >= 300) and (status < 400) then
      location := QueryLocation(FRequest);
    if Assigned(AOnStatus) then
      AOnStatus(status);
    repeat
      if IsCancelled then
        Exit(Fail(hekCancelled));
      avail := 0;
      if not WinHttpQueryDataAvailable(FRequest, @avail) then
        Exit(Fail(hekOther));
      if avail = 0 then
        Break;                                        { the whole body has come }
      SetLength(buf, avail);
      got := 0;
      if not WinHttpReadData(FRequest, PAnsiChar(buf), avail, @got) then
        Exit(Fail(hekOther));
      SetLength(buf, got);
      if (got > 0) and Assigned(AOnData) and not AOnData(buf) then
      begin
        Cancel;
        Exit(Fail(hekCancelled));
      end;
    until False;
  finally
    CloseRequest;                                     { once, under FLock }
    if conn <> nil then
      WinHttpCloseHandle(conn);
    WinHttpCloseHandle(session);
  end;
  Result.Status := FStatus;
  Result.Error := hekNone;
  Result.Location := location;
end;

{$ENDIF}

end.
