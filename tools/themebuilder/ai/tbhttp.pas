unit tbhttp;
{ The HTTP the AI page needs: one POST, the reply streamed back as it arrives, stoppable
  from another thread. Why not a library: the tool must reach HTTPS through the system's
  proxy and certificates on three platforms without shipping OpenSSL (spec §2, decision 8),
  and FPC 3.2.2's own clients either know only OpenSSL 1.1 (fphttpclient) or link the
  library at build time (the libcurl unit) -- a Linux without libcurl would then not start
  the editor at all. So:

    Windows        WinHTTP, declared in tbhttpwin (the system's proxy settings)
    Linux / macOS  the system's libcurl, loaded at run time in tbhttpcurl; when it is not
                   there only AI is off, and TbCreateTransport says why

  Execute blocks: the caller runs it on a worker thread (tbaiclient / tbaisession) and gets
  the status once, then the body piece by piece, on that thread. Cancel may come from any
  thread at any time. A redirect is never followed (WinHTTP's policy is set to never,
  libcurl does not follow unless told to): the 3xx comes back as the status, with its
  Location.

  This unit and the two transports use the RTL and FCL only -- no LCL: the same sources are
  compiled in WSL by tools/themebuilder-curl-wsl to run the libcurl path. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, StrUtils;

resourcestring
  rsTbAiNoCurl = 'libcurl was not found (tried %s). Install libcurl (for example the libcurl4 package) to use AI.';

type
  TTbHttpErrorKind = (hekNone, hekCancelled, hekNoTransport, hekBadUrl, hekNameNotResolved,
    hekCannotConnect, hekTls, hekTimeout, hekBroken, hekOther);

  TTbHttpRequest = record
    Url: string;
    Headers: TStringArray;        { 'Name: value', one per item }
    Body: RawByteString;          { UTF-8 }
    ConnectTimeoutMs: Integer;    { 0 = TbDefaultConnectTimeoutMs }
    IdleTimeoutMs: Integer;       { no byte for this long = hekTimeout; 0 = 120000 }
  end;

  TTbHttpResult = record
    Status: Integer;              { 0 when no response came }
    Error: TTbHttpErrorKind;      { hekNone also for a 3xx / 4xx / 5xx: that is Status's business }
    Detail: string;               { the system's words (error code, message); never headers or body }
    { a 3xx: the Location it named, as sent. Never followed: the request carries the key in
      a header, and a redirect to another host would take the key along (WinHTTP's default
      policy does exactly that); the user decides whether the new address is right }
    Location: string;
  end;

  { both on the worker thread, in this order: the status once, after the headers; then the
    body as it comes. Returning False from AOnData stops the transfer (hekCancelled). }
  TTbHttpStatusEvent = procedure(AStatus: Integer) of object;
  TTbHttpDataEvent = function(const AData: RawByteString): Boolean of object;

  TTbHttpTransport = class
  public
    { blocking; once per instance }
    function Execute(const ARequest: TTbHttpRequest; AOnStatus: TTbHttpStatusEvent;
      AOnData: TTbHttpDataEvent): TTbHttpResult; virtual; abstract;
    { any thread, any time; Execute returns hekCancelled soon }
    procedure Cancel; virtual; abstract;
  end;

  TTbUrlParts = record
    Secure: Boolean;
    Host: string;                 { no brackets for IPv6 }
    Port: Word;
    Path: string;                 { with the query; '/' at least }
  end;

const
  TbDefaultConnectTimeoutMs = 15000;
  TbDefaultIdleTimeoutMs = 120000;
  TbUserAgent = 'TyControls-ThemeBuilder/3.1';

{ http:// and https:// only (any case); [v6]:port; no port = 80 / 443; '#...' dropped }
function TbSplitUrl(const AUrl: string; out AParts: TTbUrlParts): Boolean;
{ localhost, 127.x.x.x, ::1 }
function TbIsLoopbackHost(const AHost: string): Boolean;
{ http:// (not https) to a host that is not this computer: what is sent crosses the
  network readable by anyone on the way. False for an address that does not split }
function TbIsPlainRemote(const AUrl: string): Boolean;
{ nil + AReason when this platform cannot do HTTP (no libcurl) }
function TbCreateTransport(out AReason: string): TTbHttpTransport;
function TbTransportAvailable(out AReason: string): Boolean;
{ the timeouts a request asks for, the defaults filled in }
function TbConnectTimeoutMs(const ARequest: TTbHttpRequest): Integer;
function TbIdleTimeoutMs(const ARequest: TTbHttpRequest): Integer;

type
  TTbTransportFactory = function(out AReason: string): TTbHttpTransport;

var
  { FOR THE TESTS: TbCreateTransport hands out what this makes instead (a transport that
    only records being asked), so a check that a request must NOT go out never reaches
    the network even when the check is broken }
  TbTransportFactoryForTest: TTbTransportFactory = nil;

implementation

uses
  {$IFDEF MSWINDOWS} tbhttpwin {$ELSE} tbhttpcurl {$ENDIF};

function AllDigits(const S: string): Boolean;
var
  i: Integer;
begin
  Result := S <> '';
  for i := 1 to Length(S) do
    if not (S[i] in ['0'..'9']) then
      Exit(False);
end;

function TbSplitUrl(const AUrl: string; out AParts: TTbUrlParts): Boolean;
var
  s, auth, portText: string;
  p, port: Integer;
begin
  Result := False;
  AParts := Default(TTbUrlParts);
  s := Trim(AUrl);
  if AnsiStartsText('https://', s) then
  begin
    AParts.Secure := True;
    Delete(s, 1, 8);
  end
  else if AnsiStartsText('http://', s) then
    Delete(s, 1, 7)
  else
    Exit;
  p := Pos('#', s);
  if p > 0 then
    SetLength(s, p - 1);
  { the authority runs to the first / or ? }
  p := 1;
  while (p <= Length(s)) and not (s[p] in ['/', '?']) do
    Inc(p);
  auth := Copy(s, 1, p - 1);
  AParts.Path := Copy(s, p, MaxInt);
  if AParts.Path = '' then
    AParts.Path := '/'
  else if AParts.Path[1] = '?' then
    AParts.Path := '/' + AParts.Path;
  { user:password@ is not for us, but it is not the host either }
  p := RPos('@', auth);
  if p > 0 then
    Delete(auth, 1, p);
  portText := '';
  if (auth <> '') and (auth[1] = '[') then
  begin
    p := Pos(']', auth);
    if p = 0 then Exit;
    AParts.Host := Copy(auth, 2, p - 2);
    Delete(auth, 1, p);
    if auth <> '' then
    begin
      if auth[1] <> ':' then Exit;
      portText := Copy(auth, 2, MaxInt);
      if portText = '' then Exit;
    end;
  end
  else
  begin
    p := RPos(':', auth);
    if p > 0 then
    begin
      AParts.Host := Copy(auth, 1, p - 1);
      portText := Copy(auth, p + 1, MaxInt);
      if portText = '' then Exit;
    end
    else
      AParts.Host := auth;
  end;
  if AParts.Host = '' then Exit;
  if portText <> '' then
  begin
    if (not AllDigits(portText)) or (Length(portText) > 5) then Exit;
    port := StrToInt(portText);
    if (port < 1) or (port > 65535) then Exit;
    AParts.Port := port;
  end
  else if AParts.Secure then
    AParts.Port := 443
  else
    AParts.Port := 80;
  Result := True;
end;

function TbIsLoopbackHost(const AHost: string): Boolean;
var
  i: Integer;
begin
  if SameText(AHost, 'localhost') or (AHost = '::1') then
    Exit(True);
  Result := False;
  if Copy(AHost, 1, 4) <> '127.' then Exit;
  for i := 5 to Length(AHost) do
    if not (AHost[i] in ['0'..'9', '.']) then
      Exit;
  Result := Length(AHost) > 4;
end;

function TbIsPlainRemote(const AUrl: string): Boolean;
var
  p: TTbUrlParts;
begin
  Result := TbSplitUrl(AUrl, p) and not p.Secure and not TbIsLoopbackHost(p.Host);
end;

function TbCreateTransport(out AReason: string): TTbHttpTransport;
begin
  AReason := '';
  if Assigned(TbTransportFactoryForTest) then
    Exit(TbTransportFactoryForTest(AReason));
  {$IFDEF MSWINDOWS}
  Result := TTbWinHttpTransport.Create;
  {$ELSE}
  if TbCurlLoad(AReason) then
    Result := TTbCurlTransport.Create
  else
    Result := nil;
  {$ENDIF}
end;

function TbTransportAvailable(out AReason: string): Boolean;
begin
  AReason := '';
  {$IFDEF MSWINDOWS}
  Result := True;
  {$ELSE}
  Result := TbCurlLoad(AReason);
  {$ENDIF}
end;

function TbConnectTimeoutMs(const ARequest: TTbHttpRequest): Integer;
begin
  Result := ARequest.ConnectTimeoutMs;
  if Result <= 0 then
    Result := TbDefaultConnectTimeoutMs;
end;

function TbIdleTimeoutMs(const ARequest: TTbHttpRequest): Integer;
begin
  Result := ARequest.IdleTimeoutMs;
  if Result <= 0 then
    Result := TbDefaultIdleTimeoutMs;
end;

end.
