unit tbaiclient;
{ One streamed AI request, start to finish, on the caller's (worker) thread: the transport
  (tbhttp), the event reader (tbsse), the format (tbaiformat), and what came of it as one
  of a fixed set of outcomes -- each told to the user in one sentence (TbAiErrorSentence).

  How the outcome is decided, the first that holds:
    0. a key and an http:// address that is not this computer: nothing is sent;
    1. the transport failed: cancelled, or which way it failed (no host, no connection,
       TLS, silence for too long, the line broken off);
    2. the service answered 3xx: a redirect, not followed (the key would go along to
       wherever it points), told with the host it named; 4xx / 5xx: the key (401 / 403),
       the address or the model (404), too many requests (429), a refused request (other
       4xx), the service's trouble (5xx);
    3. the stream carried an error;
    4. the model declined, or the reply hit the maximum output length;
    5. no event at all: a service that answered the whole reply as one JSON is taken as it
       is; anything else is not in the expected format;
    6. events, but the service never said it was finished ([DONE], a finish_reason,
       message_stop): the reply is not complete;
    7. otherwise fine.
  The text that arrived is kept in every case (the page shows it).

  The key travels in a request header and nowhere else. Every string that leaves this unit
  (the Detail, the sentence) goes through TbScrubSecret first: OpenAI's 401 message quotes
  the key half-masked ("sk-proj-****ab12").

  No LCL: the WSL console program compiles it too. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, SyncObjs, StrUtils, tbhttp, tbsse, tbaiformat;

resourcestring
  rsTbAiCancelled = 'Stopped.';
  rsTbAiNoTransport = 'AI is not available: %s';
  rsTbAiBadUrl = 'The service address is not a web address: %s';
  rsTbAiNameNotResolved = 'Cannot find the host %s. Check the address and the network.';
  rsTbAiCannotConnect = 'Cannot connect to %s. Is the service running, or does it need a proxy?';
  rsTbAiTls = 'The secure connection to %s failed.';
  rsTbAiTimeout = 'No reply from %s for %d seconds.';
  rsTbAiBroken = 'The connection to %s broke off before the reply was complete.';
  rsTbAiAuth = 'The key was refused (%d). Check the key in the AI settings.';
  rsTbAiNotFound = 'Wrong address or model name (404).';
  rsTbAiRateLimit = 'Too many requests (429). Wait a little and try again.';
  rsTbAiBadRequest = 'The service refused the request (%d).';
  rsTbAiServer = 'The service had a problem (%d). Try again later.';
  rsTbAiStreamError = 'The service stopped with an error.';
  rsTbAiBadFormat = 'The reply is not in the expected format.';
  rsTbAiTruncated = 'The reply reached the maximum output length and was cut off. Raise it in the AI settings.';
  rsTbAiRefused = 'The model declined the request.';
  rsTbAiOther = 'The request failed.';
  rsTbAiServiceSays = '(%s)';
  rsTbAiRedirect = 'The service answered with a redirect (%d) to %s. It was not followed: if that is the right address, put it in the AI settings.';
  rsTbAiInsecureKey = 'Not sent: over http:// the key would cross the network to %s unencrypted. Use an https:// address, or no key for a service on your own network.';

type
  TTbAiErrorKind = (aekNone, aekCancelled, aekNoTransport, aekBadUrl, aekNameNotResolved,
    aekCannotConnect, aekTls, aekTimeout, aekBroken, aekAuth, aekNotFound, aekRateLimit,
    aekBadRequest, aekServer, aekBadFormat, aekTruncated, aekRefused, aekRedirect,
    aekInsecureKey, aekOther);

  TTbAiResult = record
    Kind: TTbAiErrorKind;
    Status: Integer;
    Text: string;                 { all the answer text that arrived (also when it failed) }
    Detail: string;               { the service's or the system's words, scrubbed }
    RedirectTo: string;           { aekRedirect: the host the Location named (no path, no query) }
  end;

  { on the WORKER thread }
  TTbAiDeltaEvent = procedure(Sender: TObject; APiece: TTbStreamPiece; const AText: string) of object;

  TTbAiClient = class
  private
    FProfile: TTbAiProfile;
    FKey: string;
    FLock: TCriticalSection;
    FTransport: TTbHttpTransport;
    FCancelled: Boolean;
    FStatus: Integer;
    FRaw: RawByteString;
    FParser: TTbSseParser;
    FText: string;
    FDone, FTruncated, FRefused: Boolean;
    FStreamError: string;
    FEvents: Integer;
    FThinkingSent: Boolean;
    FThinkingAt: QWord;
    FOnDelta: TTbAiDeltaEvent;
    function IsCancelled: Boolean;
    procedure HttpStatus(AStatus: Integer);
    function HttpData(const AData: RawByteString): Boolean;
    procedure SseEvent(const AEvent: TTbSseEvent);
    procedure Delta(APiece: TTbStreamPiece; const AText: string);
    function DoRun(const ASystem: string; const AMessages: TTbChatMessages;
      AOnDelta: TTbAiDeltaEvent): TTbAiResult;
  public
    constructor Create(const AProfile: TTbAiProfile; const AKey: string);
    destructor Destroy; override;
    { blocking; once per instance }
    function Run(const ASystem: string; const AMessages: TTbChatMessages;
      AOnDelta: TTbAiDeltaEvent): TTbAiResult;
    procedure Cancel;                              { any thread }
    property Profile: TTbAiProfile read FProfile;
  end;

function TbAiErrorSentence(const AResult: TTbAiResult; const AProfile: TTbAiProfile): string;
function TbScrubSecret(const AText, AKey: string): string;
function TbHostOf(const AUrl: string): string;    { for the sentences and "Sent to" }

implementation

const
  cMaxRawOk = 256 * 1024;      { kept of a 2xx body, for the "not streamed" fallback }
  cMaxRawError = 64 * 1024;    { kept of an error body }

function TbHostOf(const AUrl: string): string;
var
  p: TTbUrlParts;
begin
  if TbSplitUrl(AUrl, p) then
    Result := p.Host
  else
    Result := AUrl;
end;

function StripControls(const S: string): string;
var
  i: Integer;
begin
  Result := S;
  for i := 1 to Length(Result) do
    if Result[i] < ' ' then
      Result[i] := ' ';
end;

{ the host a redirect's Location names -- never its path or query (they may hold a token);
  a relative Location stays on the request's host; '?' when it cannot be read }
function RedirectHost(const ALocation, ARequestUrl: string): string;
var
  p: TTbUrlParts;
  loc: string;
begin
  loc := Trim(ALocation);
  if TbSplitUrl(loc, p) then
    Exit(p.Host);
  if (loc <> '') and (loc[1] = '/') and (Copy(loc, 1, 2) <> '//') and TbSplitUrl(ARequestUrl, p) then
    Exit(p.Host);
  Result := '?';
end;

{ a key shown with its middle hidden: up to six of its first characters, a mask (an
  ellipsis, three dots or stars), up to four of its last -- "sk-te…9zz", "sk-...wxyz";
  ALowWord and ALowKey in lower case }
function MaskedForm(const ALowWord, ALowKey: string): Boolean;
const
  cEllipsis = #$E2#$80#$A6;
var
  p, len, k: Integer;
  before, after: string;
begin
  Result := False;
  p := Pos(cEllipsis, ALowWord);
  len := 3;
  if p = 0 then
    p := Pos('...', ALowWord);
  if p = 0 then
  begin
    p := Pos('*', ALowWord);
    len := 1;
    if p > 0 then
      while (p + len <= Length(ALowWord)) and (ALowWord[p + len] = '*') do
        Inc(len);
  end;
  if p = 0 then Exit;
  before := Copy(ALowWord, 1, p - 1);
  after := Copy(ALowWord, p + len, MaxInt);
  while (after <> '') and (after[1] in ['.', '*']) do
    Delete(after, 1, 1);
  { the key's start right before the mask, or its end right after it }
  for k := 6 downto 3 do
    if (Length(before) >= k) and
       (Copy(before, Length(before) - k + 1, k) = Copy(ALowKey, 1, k)) then
      Exit(True);
  for k := 4 downto 3 do
    if (Length(after) >= k) and (Copy(after, 1, k) = Copy(ALowKey, Length(ALowKey) - k + 1, k)) then
      Exit(True);
end;

{ any eight characters in a row of the key }
function HasKeyPiece(const ALowWord, ALowKey: string): Boolean;
var
  i: Integer;
begin
  for i := 1 to Length(ALowKey) - 7 do
    if Pos(Copy(ALowKey, i, 8), ALowWord) > 0 then
      Exit(True);
  Result := False;
end;

function TbScrubSecret(const AText, AKey: string): string;
const
  cBreaks = [' ', #9, #10, #13, '"', '''', ',', '(', ')', '[', ']', '{', '}', '<', '>', '=',
    '&', '`'];
var
  i, start, coreEnd, p: Integer;
  word, core, lowCore, rest, lowKey, head, tail, text: string;
  keyed: Boolean;
begin
  lowKey := LowerCase(AKey);
  text := AText;
  { a short key: no part of it can be told from ordinary words, so the whole of it goes,
    wherever it stands (any case) }
  if (AKey <> '') and (Length(AKey) < 8) then
  begin
    p := Pos(lowKey, LowerCase(text));
    while p > 0 do
    begin
      text := Copy(text, 1, p - 1) + '***' + Copy(text, p + Length(AKey), MaxInt);
      p := Pos(lowKey, LowerCase(text));
    end;
  end;
  keyed := Length(AKey) >= 8;
  if keyed then
  begin
    head := Copy(lowKey, 1, 6);
    tail := Copy(lowKey, Length(lowKey) - 3, 4);
  end;
  Result := '';
  i := 1;
  while i <= Length(text) do
  begin
    if text[i] in cBreaks then
    begin
      Result := Result + text[i];
      Inc(i);
      Continue;
    end;
    start := i;
    while (i <= Length(text)) and not (text[i] in cBreaks) do
      Inc(i);
    word := Copy(text, start, i - start);
    { a word that ends a sentence: look at it without its full stops }
    coreEnd := Length(word);
    while (coreEnd > 0) and (word[coreEnd] in ['.', ';', ')', ':']) do
      Dec(coreEnd);
    core := Copy(word, 1, coreEnd);
    rest := Copy(word, coreEnd + 1, MaxInt);
    lowCore := LowerCase(core);
    if (Pos('***', core) > 0)
       or (keyed and ((Pos(lowKey, lowCore) > 0) or (Pos(head, lowCore) > 0) or
         (Pos(tail, lowCore) > 0) or MaskedForm(lowCore, lowKey) or HasKeyPiece(lowCore, lowKey))) then
      Result := Result + '***' + rest
    else
      Result := Result + word;
  end;
end;

function TbAiErrorSentence(const AResult: TTbAiResult; const AProfile: TTbAiProfile): string;
var
  host: string;
  secs: Integer;
  withDetail: Boolean;
begin
  host := TbHostOf(AProfile.BaseUrl);
  withDetail := True;
  case AResult.Kind of
    aekNone: Result := '';
    aekCancelled:
      begin
        Result := rsTbAiCancelled;
        withDetail := False;
      end;
    aekNoTransport:
      begin
        Result := Format(rsTbAiNoTransport, [AResult.Detail]);
        withDetail := False;
      end;
    aekBadUrl: Result := Format(rsTbAiBadUrl, [AProfile.BaseUrl]);
    aekNameNotResolved: Result := Format(rsTbAiNameNotResolved, [host]);
    aekCannotConnect: Result := Format(rsTbAiCannotConnect, [host]);
    aekTls: Result := Format(rsTbAiTls, [host]);
    aekTimeout:
      begin
        secs := AProfile.TimeoutSec;
        if secs <= 0 then
          secs := TbDefaultIdleTimeoutMs div 1000;
        Result := Format(rsTbAiTimeout, [host, secs]);
      end;
    aekBroken: Result := Format(rsTbAiBroken, [host]);
    aekAuth: Result := Format(rsTbAiAuth, [AResult.Status]);
    aekNotFound: Result := rsTbAiNotFound;
    aekRateLimit: Result := rsTbAiRateLimit;
    aekBadRequest: Result := Format(rsTbAiBadRequest, [AResult.Status]);
    aekServer:
      if AResult.Status < 400 then
        Result := rsTbAiStreamError        { the stream itself carried the error }
      else
        Result := Format(rsTbAiServer, [AResult.Status]);
    aekBadFormat: Result := rsTbAiBadFormat;
    aekTruncated: Result := rsTbAiTruncated;
    aekRefused: Result := rsTbAiRefused;
    aekRedirect:
      begin
        Result := Format(rsTbAiRedirect, [AResult.Status, AResult.RedirectTo]);
        withDetail := False;
      end;
    aekInsecureKey:
      begin
        Result := Format(rsTbAiInsecureKey, [host]);
        withDetail := False;
      end;
  else
    Result := rsTbAiOther;
  end;
  if withDetail and (Result <> '') and (AResult.Detail <> '') then
    Result := Result + ' ' + Format(rsTbAiServiceSays, [AResult.Detail]);
end;

{ ---- TTbAiClient ---- }

constructor TTbAiClient.Create(const AProfile: TTbAiProfile; const AKey: string);
begin
  inherited Create;
  FProfile := AProfile;
  FKey := AKey;
  FLock := TCriticalSection.Create;
end;

destructor TTbAiClient.Destroy;
begin
  FLock.Free;
  inherited Destroy;
end;

function TTbAiClient.IsCancelled: Boolean;
begin
  FLock.Enter;
  try
    Result := FCancelled;
  finally
    FLock.Leave;
  end;
end;

procedure TTbAiClient.Cancel;
begin
  FLock.Enter;
  try
    FCancelled := True;
    if FTransport <> nil then
      FTransport.Cancel;
  finally
    FLock.Leave;
  end;
end;

procedure TTbAiClient.Delta(APiece: TTbStreamPiece; const AText: string);
begin
  if Assigned(FOnDelta) then
    FOnDelta(Self, APiece, AText);
end;

procedure TTbAiClient.HttpStatus(AStatus: Integer);
begin
  FStatus := AStatus;
end;

function TTbAiClient.HttpData(const AData: RawByteString): Boolean;
begin
  if (FStatus >= 200) and (FStatus < 300) then
  begin
    if Length(FRaw) < cMaxRawOk then
      FRaw := FRaw + Copy(AData, 1, cMaxRawOk - Length(FRaw));
    FParser.Feed(AData);
  end
  else if Length(FRaw) < cMaxRawError then
    FRaw := FRaw + Copy(AData, 1, cMaxRawError - Length(FRaw));
  Result := not IsCancelled;
end;

procedure TTbAiClient.SseEvent(const AEvent: TTbSseEvent);
var
  d: TTbStreamDelta;
  t: QWord;
begin
  { the service said it was finished ([DONE], message_stop, a finish_reason): whatever
    follows -- a late error, more text, a heartbeat -- is not part of this reply }
  if FDone then Exit;
  d := TbParseStreamEvent(FProfile.Format, AEvent);
  if d.NotJson then Exit;      { a heartbeat }
  Inc(FEvents);
  case d.Kind of
    tspText:
      begin
        FText := FText + d.Text;
        Delta(tspText, d.Text);
      end;
    tspThinking:
      begin
        { once at first, then at most once a second: the page only says "thinking" }
        t := GetTickCount64;
        if (not FThinkingSent) or (t - FThinkingAt >= 1000) then
        begin
          FThinkingSent := True;
          FThinkingAt := t;
          Delta(tspThinking, '');
        end;
      end;
    tspError:
      begin
        FStreamError := d.Text;
        if FStreamError = '' then
          FStreamError := 'error';
      end;
  end;
  case d.Ends of
    tspDone: FDone := True;
    tspTruncated: FTruncated := True;
    tspRefused: FRefused := True;
  end;
  case d.Kind of
    tspDone: FDone := True;
    tspTruncated: FTruncated := True;
    tspRefused: FRefused := True;
  end;
end;

{ whatever is raised on the way (a transport, a parser, out of memory) ends as one outcome
  -- its words scrubbed like every other string that leaves this unit }
function TTbAiClient.Run(const ASystem: string; const AMessages: TTbChatMessages;
  AOnDelta: TTbAiDeltaEvent): TTbAiResult;
begin
  try
    Result := DoRun(ASystem, AMessages, AOnDelta);
  except
    on E: Exception do
    begin
      Result := Default(TTbAiResult);
      Result.Kind := aekOther;
      Result.Text := FText;
      Result.Detail := TbScrubSecret(Trim(StripControls(E.Message)), FKey);
    end;
  end;
end;

function TTbAiClient.DoRun(const ASystem: string; const AMessages: TTbChatMessages;
  AOnDelta: TTbAiDeltaEvent): TTbAiResult;
var
  reason, detail, whole: string;
  req: TTbHttpRequest;
  http: TTbHttpResult;
  transport: TTbHttpTransport;
begin
  Result := Default(TTbAiResult);
  FOnDelta := AOnDelta;
  FStatus := 0;
  FRaw := '';
  FText := '';
  FDone := False;
  FTruncated := False;
  FRefused := False;
  FStreamError := '';
  FEvents := 0;
  FThinkingSent := False;
  if IsCancelled then
  begin
    Result.Kind := aekCancelled;
    Exit;
  end;
  { a key never goes out in the clear: http:// is for this computer, or for a service on
    the user's own network that needs no key (a local Ollama on another machine) }
  if (FKey <> '') and TbIsPlainRemote(TbEndpointUrl(FProfile)) then
  begin
    Result.Kind := aekInsecureKey;
    Exit;
  end;
  transport := TbCreateTransport(reason);
  if transport = nil then
  begin
    Result.Kind := aekNoTransport;
    Result.Detail := reason;
    Exit;
  end;
  FLock.Enter;
  FTransport := transport;
  FLock.Leave;
  req := Default(TTbHttpRequest);
  req.Url := TbEndpointUrl(FProfile);
  req.Headers := TbRequestHeaders(FProfile, FKey);
  req.Body := TbRequestBody(FProfile, ASystem, AMessages);
  req.ConnectTimeoutMs := TbDefaultConnectTimeoutMs;
  if FProfile.TimeoutSec > 0 then
    req.IdleTimeoutMs := FProfile.TimeoutSec * 1000
  else
    req.IdleTimeoutMs := TbDefaultIdleTimeoutMs;
  http := Default(TTbHttpResult);
  FParser := TTbSseParser.Create(@SseEvent);
  try
    if IsCancelled then
      http.Error := hekCancelled
    else
      http := transport.Execute(req, @HttpStatus, @HttpData);
    FParser.Finish;
    detail := '';
    Result.Status := FStatus;
    if (http.Error = hekCancelled) or IsCancelled then
      Result.Kind := aekCancelled
    else if http.Error <> hekNone then
    begin
      case http.Error of
        hekNoTransport: Result.Kind := aekNoTransport;
        hekBadUrl: Result.Kind := aekBadUrl;
        hekNameNotResolved: Result.Kind := aekNameNotResolved;
        hekCannotConnect: Result.Kind := aekCannotConnect;
        hekTls: Result.Kind := aekTls;
        hekTimeout: Result.Kind := aekTimeout;
        hekBroken: Result.Kind := aekBroken;
      else
        Result.Kind := aekOther;
      end;
      detail := http.Detail;
    end
    else if (FStatus >= 300) and (FStatus < 400) then
    begin
      { not followed (tbhttp): the user decides whether the address it names is right }
      Result.Kind := aekRedirect;
      Result.RedirectTo := RedirectHost(http.Location, req.Url);
    end
    else if (FStatus < 200) or (FStatus >= 300) then
    begin
      case FStatus of
        401, 403: Result.Kind := aekAuth;
        404: Result.Kind := aekNotFound;
        429: Result.Kind := aekRateLimit;
        400, 402, 405..428, 430..499: Result.Kind := aekBadRequest;
        500..599: Result.Kind := aekServer;
      else
        Result.Kind := aekOther;
      end;
      detail := TbErrorBodyMessage(FRaw);
    end
    else if FStreamError <> '' then
    begin
      { an error the service sent before it said it was finished (after that, SseEvent
        does not look) }
      Result.Kind := aekServer;
      detail := FStreamError;
    end
    else if FRefused then
      Result.Kind := aekRefused
    else if FTruncated then
      Result.Kind := aekTruncated
    else if FEvents = 0 then
    begin
      if TbParseWholeReply(FProfile.Format, FRaw, whole) then
      begin
        { a service that does not stream: the whole reply at once }
        FText := whole;
        Delta(tspText, whole);
        Result.Kind := aekNone;
      end
      else
      begin
        Result.Kind := aekBadFormat;
        detail := Trim(StripControls(Copy(FRaw, 1, 80)));
      end;
    end
    else if not FDone then
      Result.Kind := aekBroken     { the service never said it was finished }
    else
      Result.Kind := aekNone;
  finally
    FLock.Enter;
    FTransport := nil;
    FLock.Leave;
    transport.Free;
    FreeAndNil(FParser);
  end;
  Result.Text := FText;
  Result.Detail := TbScrubSecret(detail, FKey);
end;

end.
