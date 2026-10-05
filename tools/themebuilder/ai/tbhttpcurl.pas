unit tbhttpcurl;
{ The HTTP transport on Linux and macOS: the system's libcurl, loaded when it is first
  needed (dynlibs), never linked. FPC's libcurl unit declares every function "external"
  -- a program using it needs libcurl to start at all, and spec §2 (decision 8) wants a
  Linux without libcurl to lose AI and nothing else. So a small table of nine functions is
  filled with GetProcedureAddress, and the constants are copied from FPC's libcurl.pp (the
  unit is not used, not even for them: that would bring -lcurl into the link).

  Which library: $THEMEBUILDER_LIBCURL when it is set (and then only it: a distribution
  with an odd name, and how to see the "not found" page on purpose), else the usual names
  in order (TbCurlCandidates). A library that lacks one of the nine counts as not found.

  THE VARIADIC CALLS. curl_easy_setopt and curl_easy_getinfo are C variadic functions. They
  are called in exactly one place each (CurlSetOpt, CurlGetInfo) through a cdecl procedural
  type ending in "array of const", which FPC passes as C varargs; the argument is always
  pointer-sized (Pointer(PtrInt(x)) for a C long -- on LP64 Linux / macOS, and on 32-bit
  ILP32 too, a long is as wide as a pointer). On x86-64 and on Linux arm64 variadic integer
  arguments travel like ordinary ones; on Apple arm64 they go on the stack, so whether this
  is right there depends on FPC's handling of cdecl "array of const" on aarch64-darwin.
  It cannot be tried on this project's machines (Windows, WSL): the acceptance list checks
  it on a real Mac. If it is wrong there, the fallback is to run /usr/bin/curl as a process
  on macOS (not done in phase 3).

  Proxies: libcurl reads http_proxy / https_proxy / no_proxy itself; a loopback address is
  told to use none. Redirects are not followed (CURLOPT_FOLLOWLOCATION 0, libcurl's own
  default, set anyway): the 3xx is the status, CURLINFO_REDIRECT_URL its Location. Every
  curl_easy_setopt's answer is checked: an option this libcurl refuses ends the request
  before anything is sent (hekOption, naming it).

  A limit: a cancel is seen in the progress callback, which libcurl does not call while it
  resolves the host name (the system's resolver blocks) -- Stop during a slow DNS lookup
  takes effect when the lookup ends or the connect timeout (15 s) runs out. The idle timeout is libcurl's low-speed check (under 1 byte a second for
  that many seconds). Cancel only raises a flag: the progress callback (about once a second
  even when idle) and the write callback see it and stop the transfer. }
{$mode objfpc}{$H+}
interface

{$IFDEF UNIX}
uses
  Classes, SysUtils, SyncObjs, dynlibs, tbhttp;

type
  TTbCurlTransport = class(TTbHttpTransport)
  private
    FLock: TCriticalSection;
    FCancelled: Boolean;
    FOnStatus: TTbHttpStatusEvent;
    FOnData: TTbHttpDataEvent;
    FHandle: Pointer;
    FStatus: Integer;
    FStatusSent: Boolean;
    FErrBuf: array[0..255] of Char;   { CURL_ERROR_SIZE }
    function IsCancelled: Boolean;
    procedure MarkCancelled;
    procedure SendStatusOnce;
  public
    constructor Create;
    destructor Destroy; override;
    function Execute(const ARequest: TTbHttpRequest; AOnStatus: TTbHttpStatusEvent;
      AOnData: TTbHttpDataEvent): TTbHttpResult; override;
    procedure Cancel; override;
  end;

var
  { FOR THE TESTS: curl_easy_setopt answers CURLE_UNKNOWN_OPTION for this option (0 = none),
    as an old libcurl would }
  TbCurlRefuseOptionForTest: LongInt = 0;

const
  TbCurlOptNoSignal = 99;               { CURLOPT_NOSIGNAL, for the test above }

function TbCurlCandidates: TStringArray;            { $THEMEBUILDER_LIBCURL alone when set }
function TbCurlLoad(out AReason: string): Boolean;  { once; the result is kept }
function TbCurlLoadedName: string;
function TbCurlErrorKind(ACode: LongInt): TTbHttpErrorKind;
{$ENDIF}

implementation

{$IFDEF UNIX}

type
  TCurlGlobalInit = function(flags: LongInt): LongInt; cdecl;
  TCurlEasyInit = function: Pointer; cdecl;
  TCurlEasySetopt = function(h: Pointer; opt: LongInt; args: array of const): LongInt; cdecl;
  TCurlEasyGetinfo = function(h: Pointer; info: LongInt; args: array of const): LongInt; cdecl;
  TCurlEasyPerform = function(h: Pointer): LongInt; cdecl;
  TCurlEasyCleanup = procedure(h: Pointer); cdecl;
  TCurlEasyStrerror = function(code: LongInt): PChar; cdecl;
  TCurlSlistAppend = function(list: Pointer; s: PChar): Pointer; cdecl;
  TCurlSlistFreeAll = procedure(list: Pointer); cdecl;

  TCurlTable = record
    GlobalInit: TCurlGlobalInit;
    EasyInit: TCurlEasyInit;
    EasySetopt: TCurlEasySetopt;
    EasyGetinfo: TCurlEasyGetinfo;
    EasyPerform: TCurlEasyPerform;
    EasyCleanup: TCurlEasyCleanup;
    EasyStrerror: TCurlEasyStrerror;
    SlistAppend: TCurlSlistAppend;
    SlistFreeAll: TCurlSlistFreeAll;
  end;

const
  { from FPC's packages/libcurl/src/libcurl.pp }
  CURLOPT_WRITEDATA = 10001;
  CURLOPT_URL = 10002;
  CURLOPT_PROXY = 10004;
  CURLOPT_ERRORBUFFER = 10010;
  CURLOPT_WRITEFUNCTION = 20011;
  CURLOPT_POSTFIELDS = 10015;
  CURLOPT_USERAGENT = 10018;
  CURLOPT_LOW_SPEED_LIMIT = 19;
  CURLOPT_LOW_SPEED_TIME = 20;
  CURLOPT_HTTPHEADER = 10023;
  CURLOPT_NOPROGRESS = 43;
  CURLOPT_POST = 47;
  CURLOPT_XFERINFODATA = 10057;
  CURLOPT_POSTFIELDSIZE = 60;
  CURLOPT_CONNECTTIMEOUT = 78;
  CURLOPT_NOSIGNAL = 99;
  CURLOPT_XFERINFOFUNCTION = 20219;
  CURLOPT_FOLLOWLOCATION = 52;
  CURLINFO_RESPONSE_CODE = $200002;
  CURLINFO_REDIRECT_URL = $10001F;    { CURLINFO_STRING + 31 }
  CURLINFO_HTTP_CONNECTCODE = $200016; { CURLINFO_LONG + 22: the proxy's answer to CONNECT }
  CURL_GLOBAL_DEFAULT = 3;

var
  GLoadLock: TCriticalSection = nil;
  GTried: Boolean = False;
  GOk: Boolean = False;
  GReason: string = '';
  GName: string = '';
  GLib: TLibHandle = NilHandle;
  GCurl: TCurlTable;

function TbCurlCandidates: TStringArray;
var
  env: string;
begin
  env := GetEnvironmentVariable('THEMEBUILDER_LIBCURL');
  if env <> '' then
  begin
    Result := [env];
    Exit;
  end;
  {$IFDEF DARWIN}
  Result := ['/usr/lib/libcurl.4.dylib', 'libcurl.4.dylib', 'libcurl.dylib'];
  {$ELSE}
  Result := ['libcurl.so.4', 'libcurl-gnutls.so.4', 'libcurl-nss.so.4', 'libcurl.so'];
  {$ENDIF}
end;

{ the nine functions out of ALib; '' when all are there, else the first one missing }
function Bind(ALib: TLibHandle; out ATable: TCurlTable): string;
var
  missing: string;

  function Get(const AName: string): Pointer;
  begin
    Result := GetProcedureAddress(ALib, AName);
    if (Result = nil) and (missing = '') then
      missing := AName;
  end;

begin
  missing := '';
  ATable := Default(TCurlTable);
  Pointer(ATable.GlobalInit) := Get('curl_global_init');
  Pointer(ATable.EasyInit) := Get('curl_easy_init');
  Pointer(ATable.EasySetopt) := Get('curl_easy_setopt');
  Pointer(ATable.EasyGetinfo) := Get('curl_easy_getinfo');
  Pointer(ATable.EasyPerform) := Get('curl_easy_perform');
  Pointer(ATable.EasyCleanup) := Get('curl_easy_cleanup');
  Pointer(ATable.EasyStrerror) := Get('curl_easy_strerror');
  Pointer(ATable.SlistAppend) := Get('curl_slist_append');
  Pointer(ATable.SlistFreeAll) := Get('curl_slist_free_all');
  Result := missing;
end;

function TbCurlLoad(out AReason: string): Boolean;
var
  cands: TStringArray;
  tried, missing: string;
  i: Integer;
  lib: TLibHandle;
  table: TCurlTable;
begin
  GLoadLock.Enter;
  try
    if not GTried then
    begin
      GTried := True;
      cands := TbCurlCandidates;
      tried := '';
      for i := 0 to High(cands) do
      begin
        if tried <> '' then
          tried := tried + ', ';
        lib := LoadLibrary(cands[i]);
        if lib = NilHandle then
        begin
          tried := tried + cands[i];
          Continue;
        end;
        missing := Bind(lib, table);
        if missing <> '' then
        begin
          UnloadLibrary(lib);
          tried := tried + cands[i] + ' (no ' + missing + ')';
          Continue;
        end;
        GLib := lib;
        GCurl := table;
        GName := cands[i];
        GCurl.GlobalInit(CURL_GLOBAL_DEFAULT);
        GOk := True;
        Break;
      end;
      if not GOk then
        GReason := Format(rsTbAiNoCurl, [tried]);
    end;
    AReason := GReason;
    Result := GOk;
  finally
    GLoadLock.Leave;
  end;
end;

function TbCurlLoadedName: string;
begin
  Result := GName;
end;

function TbCurlErrorKind(ACode: LongInt): TTbHttpErrorKind;
begin
  case ACode of
    1, 3: Result := hekBadUrl;
    5, 6: Result := hekNameNotResolved;
    7: Result := hekCannotConnect;
    28: Result := hekTimeout;
    35, 51, 53, 54, 58, 59, 60, 64, 66, 77, 80, 82, 83, 90, 91: Result := hekTls;
    18, 52, 55, 56: Result := hekBroken;
    23, 42: Result := hekCancelled;
  else
    Result := hekOther;
  end;
end;

{ ---- the two variadic calls: everything goes through here (see the unit's comment) ---- }

function CurlSetOpt(AHandle: Pointer; AOption: LongInt; AValue: Pointer): LongInt;
begin
  { FOR THE TESTS: a libcurl that does not know this option }
  if (TbCurlRefuseOptionForTest <> 0) and (AOption = TbCurlRefuseOptionForTest) then
    Exit(48);    { CURLE_UNKNOWN_OPTION }
  { one pointer-sized vararg; a C long is passed as Pointer(PtrInt(x)) }
  Result := GCurl.EasySetopt(AHandle, AOption, [AValue]);
end;

function CurlGetInfo(AHandle: Pointer; AInfo: LongInt; AWhere: Pointer): LongInt;
begin
  Result := GCurl.EasyGetinfo(AHandle, AInfo, [AWhere]);
end;

function CurlSetLong(AHandle: Pointer; AOption: LongInt; AValue: PtrInt): LongInt;
begin
  Result := CurlSetOpt(AHandle, AOption, Pointer(AValue));
end;

{ ---- callbacks (libcurl's thread = the one in Execute) ---- }

function CurlWrite(p: PChar; size, nmemb: PtrUInt; ud: Pointer): PtrUInt; cdecl;
var
  t: TTbCurlTransport;
  s: RawByteString;
  n: PtrUInt;
begin
  t := TTbCurlTransport(ud);
  n := size * nmemb;
  if t.IsCancelled then
    Exit(0);                       { CURLE_WRITE_ERROR: the transfer stops }
  t.SendStatusOnce;
  SetString(s, p, n);
  if Assigned(t.FOnData) and not t.FOnData(s) then
  begin
    t.MarkCancelled;
    Exit(0);
  end;
  Result := n;
end;

function CurlProgress(ud: Pointer; dltotal, dlnow, ultotal, ulnow: Int64): LongInt; cdecl;
begin
  if TTbCurlTransport(ud).IsCancelled then
    Result := 1                    { CURLE_ABORTED_BY_CALLBACK }
  else
    Result := 0;
end;

{ ---- TTbCurlTransport ---- }

constructor TTbCurlTransport.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
end;

destructor TTbCurlTransport.Destroy;
begin
  FLock.Free;
  inherited Destroy;
end;

function TTbCurlTransport.IsCancelled: Boolean;
begin
  FLock.Enter;
  try
    Result := FCancelled;
  finally
    FLock.Leave;
  end;
end;

procedure TTbCurlTransport.MarkCancelled;
begin
  FLock.Enter;
  FCancelled := True;
  FLock.Leave;
end;

procedure TTbCurlTransport.Cancel;
begin
  MarkCancelled;
end;

procedure TTbCurlTransport.SendStatusOnce;
var
  code: PtrInt;
begin
  if FStatusSent then Exit;
  code := 0;
  CurlGetInfo(FHandle, CURLINFO_RESPONSE_CODE, @code);
  if code <= 0 then Exit;
  FStatus := code;
  FStatusSent := True;
  if Assigned(FOnStatus) then
    FOnStatus(FStatus);
end;

function TTbCurlTransport.Execute(const ARequest: TTbHttpRequest;
  AOnStatus: TTbHttpStatusEvent; AOnData: TTbHttpDataEvent): TTbHttpResult;
var
  url: TTbUrlParts;
  reason, address, body, agent, msg: string;
  h, slist, appended: Pointer;
  redirect: PChar;
  i: Integer;
  code: LongInt;
  idleSec, connectSec, connectCode: PtrInt;
  refused: string;

  procedure Opt(AOption: LongInt; AValue: Pointer; const AName: string);
  var
    c: LongInt;
  begin
    c := CurlSetOpt(h, AOption, AValue);
    if (c <> 0) and (refused = '') then
      refused := Format('%s (%d)', [AName, c]);
  end;

begin
  Result := Default(TTbHttpResult);
  FStatus := 0;
  FStatusSent := False;
  FOnStatus := AOnStatus;
  FOnData := AOnData;
  if not TbSplitUrl(ARequest.Url, url) then
  begin
    Result.Error := hekBadUrl;
    Exit;
  end;
  if IsCancelled then
  begin
    Result.Error := hekCancelled;
    Exit;
  end;
  if not TbCurlLoad(reason) then
  begin
    Result.Error := hekNoTransport;
    Result.Detail := reason;
    Exit;
  end;
  h := GCurl.EasyInit();
  if h = nil then
  begin
    Result.Error := hekOther;
    Result.Detail := 'curl_easy_init failed';
    Exit;
  end;
  { these strings must live until curl_easy_perform returns: libcurl keeps the pointers
    (CURLOPT_POSTFIELDS does not copy the body) }
  address := ARequest.Url;
  body := ARequest.Body;
  agent := TbUserAgent;
  slist := nil;
  FHandle := h;
  try
    for i := 0 to High(ARequest.Headers) do
    begin
      appended := GCurl.SlistAppend(slist, PChar(ARequest.Headers[i]));
      if appended <> nil then
        slist := appended;
    end;
    { no "Expect: 100-continue" round trip before a larger body }
    appended := GCurl.SlistAppend(slist, PChar('Expect:'));
    if appended <> nil then
      slist := appended;
    connectSec := (TbConnectTimeoutMs(ARequest) + 999) div 1000;
    idleSec := (TbIdleTimeoutMs(ARequest) + 999) div 1000;
    if idleSec < 1 then
      idleSec := 1;
    FillChar(FErrBuf, SizeOf(FErrBuf), 0);
    { every option is needed (the redirect policy, the proxy bypass, the cancel hook): one
      this libcurl refuses stops the request before anything is sent, naming it }
    refused := '';
    Opt(CURLOPT_ERRORBUFFER, @FErrBuf[0], 'CURLOPT_ERRORBUFFER');
    Opt(CURLOPT_URL, PChar(address), 'CURLOPT_URL');
    Opt(CURLOPT_POST, Pointer(PtrInt(1)), 'CURLOPT_POST');
    Opt(CURLOPT_POSTFIELDS, PChar(body), 'CURLOPT_POSTFIELDS');
    Opt(CURLOPT_POSTFIELDSIZE, Pointer(PtrInt(Length(body))), 'CURLOPT_POSTFIELDSIZE');
    Opt(CURLOPT_HTTPHEADER, slist, 'CURLOPT_HTTPHEADER');
    Opt(CURLOPT_USERAGENT, PChar(agent), 'CURLOPT_USERAGENT');
    Opt(CURLOPT_WRITEFUNCTION, @CurlWrite, 'CURLOPT_WRITEFUNCTION');
    Opt(CURLOPT_WRITEDATA, Self, 'CURLOPT_WRITEDATA');
    Opt(CURLOPT_NOPROGRESS, Pointer(PtrInt(0)), 'CURLOPT_NOPROGRESS');
    Opt(CURLOPT_XFERINFOFUNCTION, @CurlProgress, 'CURLOPT_XFERINFOFUNCTION');
    Opt(CURLOPT_XFERINFODATA, Self, 'CURLOPT_XFERINFODATA');
    Opt(CURLOPT_CONNECTTIMEOUT, Pointer(connectSec), 'CURLOPT_CONNECTTIMEOUT');
    Opt(CURLOPT_LOW_SPEED_LIMIT, Pointer(PtrInt(1)), 'CURLOPT_LOW_SPEED_LIMIT');
    Opt(CURLOPT_LOW_SPEED_TIME, Pointer(idleSec), 'CURLOPT_LOW_SPEED_TIME');
    Opt(CURLOPT_NOSIGNAL, Pointer(PtrInt(1)), 'CURLOPT_NOSIGNAL');
    { libcurl's default, said out loud: a redirect would take the key to another host }
    Opt(CURLOPT_FOLLOWLOCATION, Pointer(PtrInt(0)), 'CURLOPT_FOLLOWLOCATION');
    if TbIsLoopbackHost(url.Host) then
      Opt(CURLOPT_PROXY, PChar(''), 'CURLOPT_PROXY');   { '' = no proxy for a local service }
    if refused <> '' then
    begin
      Result.Error := hekOption;
      Result.Detail := refused;
      Exit;
    end;
    code := GCurl.EasyPerform(h);
    SendStatusOnce;      { a reply with no body: the status still counts }
    Result.Status := FStatus;
    if (FStatus >= 300) and (FStatus < 400) then
    begin
      redirect := nil;
      if (CurlGetInfo(h, CURLINFO_REDIRECT_URL, @redirect) = 0) and (redirect <> nil) then
        Result.Location := StrPas(redirect);
    end;
    connectCode := 0;
    if (code <> 0) and (FStatus = 0) and
       (CurlGetInfo(h, CURLINFO_HTTP_CONNECTCODE, @connectCode) = 0) and (connectCode = 407) then
    begin
      { an https tunnel the proxy refused without a password: told as the status it is,
        as WinHTTP does }
      FStatus := 407;
      FStatusSent := True;
      if Assigned(FOnStatus) then
        FOnStatus(FStatus);
      Result.Status := FStatus;
      code := 0;
    end;
    if code <> 0 then
    begin
      if IsCancelled then
        Result.Error := hekCancelled
      else
        Result.Error := TbCurlErrorKind(code);
      msg := StrPas(PChar(@FErrBuf[0]));
      if msg = '' then
        msg := StrPas(GCurl.EasyStrerror(code));
      if Result.Error <> hekCancelled then
        Result.Detail := Format('libcurl %d: %s', [code, msg]);
    end
    else if IsCancelled then
      Result.Error := hekCancelled;
  finally
    FHandle := nil;
    if slist <> nil then
      GCurl.SlistFreeAll(slist);
    GCurl.EasyCleanup(h);
  end;
end;

initialization
  GLoadLock := TCriticalSection.Create;
finalization
  FreeAndNil(GLoadLock);
{$ENDIF}

end.
