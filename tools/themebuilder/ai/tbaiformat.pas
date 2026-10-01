unit tbaiformat;
{ The two request formats the AI page speaks, and how their streamed replies read.

  OpenAI-compatible (OpenAI, DeepSeek, Ollama's /v1, most proxies):
    POST {base}/chat/completions; "Authorization: Bearer <key>" (left out with no key);
    body: model, stream: true, messages = [system, user / assistant ...], max_tokens only
    when set (the newer OpenAI models refuse max_tokens).
    stream: "data: {...choices[0].delta.content...}" events, a last chunk with
    finish_reason (stop / length = cut off / content_filter), then "data: [DONE]".
    DeepSeek's reasoning models send delta.reasoning_content first (thinking) and
    ": keep-alive" comments. An error mid-stream: data: {"error": {"message": ...}}.
    Data that is not JSON (an empty data line, "ping" -- heartbeats from services and
    proxies) is nothing; everything after [DONE] is ignored (tbaiclient).

  Anthropic (Messages API):
    POST {base}/messages; x-api-key, anthropic-version: 2023-06-01; body: model,
    max_tokens (required), system, messages, stream: true.
    stream: event: message_start, content_block_start (text or thinking),
    content_block_delta (text_delta / thinking_delta / signature_delta),
    content_block_stop, message_delta (stop_reason: end_turn, max_tokens = cut off,
    refusal, stop_sequence), message_stop; event: ping in between;
    event: error + {"type":"error","error":{"type":..., "message":...}}.
    The current models think first by default: a thinking block, then the text.

  Both: a non-2xx body is {"error": {"message": ...}} (Ollama's own API: {"error": "..."});
  a service that does not stream may answer 2xx with the whole reply as one JSON
  (TbParseWholeReply).

  Sources: the OpenAI chat streaming reference and the Anthropic Messages streaming and
  error pages, as of 2026-10-01; the test fixtures are written after them (no key was at
  hand to record real streams) and name their source on their first line.
  No temperature is sent: today's reasoning / thinking models refuse it.

  No LCL: the WSL console program compiles it too. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpjson, jsonparser, tbsse;

type
  TTbAiFormat = (tafOpenAI, tafAnthropic);

  TTbAiProfile = record
    Id, Name: string;
    Format: TTbAiFormat;
    BaseUrl, Model: string;
    MaxOutput: Integer;           { 0 = not sent (OpenAI-compatible); Anthropic needs > 0 }
    TimeoutSec: Integer;          { idle timeout }
  end;

  TTbChatRole = (tcrUser, tcrAssistant);
  TTbChatMessage = record
    Role: TTbChatRole;
    Text: string;
  end;
  TTbChatMessages = array of TTbChatMessage;

  TTbStreamPiece = (tspNone, tspText, tspThinking, tspDone, tspTruncated, tspRefused, tspError);

  TTbStreamDelta = record
    Kind: TTbStreamPiece;
    Text: string;                 { tspText: the text; tspError: the service's message }
    { the event also ends the reply (OpenAI puts finish_reason on a chunk that may still
      carry text): tspDone, tspTruncated, tspRefused, or tspNone }
    Ends: TTbStreamPiece;
    { the data was not JSON (a proxy's heartbeat, an empty data line, "ping"): nothing --
      neither text nor an error }
    NotJson: Boolean;
  end;

const
  { Anthropic's max_tokens when the profile has none: a whole built-in theme rewritten
    (auto.tycss is 32 KB, about 8 000 tokens) plus the thinking that comes first }
  TbAnthropicDefaultMaxOutput = 32000;

function TbEndpointUrl(const AProfile: TTbAiProfile): string;
function TbRequestHeaders(const AProfile: TTbAiProfile; const AKey: string): TStringArray;
function TbRequestBody(const AProfile: TTbAiProfile; const ASystem: string;
  const AMessages: TTbChatMessages): RawByteString;
function TbParseStreamEvent(AFormat: TTbAiFormat; const AEvent: TTbSseEvent): TTbStreamDelta;
function TbParseWholeReply(AFormat: TTbAiFormat; const ABody: string; out AText: string): Boolean;
function TbErrorBodyMessage(const ABody: string): string;   { '' when none }
function TbChatMessage(ARole: TTbChatRole; const AText: string): TTbChatMessage;

implementation

function TbChatMessage(ARole: TTbChatRole; const AText: string): TTbChatMessage;
begin
  Result.Role := ARole;
  Result.Text := AText;
end;

function TbEndpointUrl(const AProfile: TTbAiProfile): string;
var
  b, tail: string;
begin
  b := Trim(AProfile.BaseUrl);
  while (b <> '') and (b[Length(b)] = '/') do
    SetLength(b, Length(b) - 1);
  if AProfile.Format = tafAnthropic then
    tail := '/messages'
  else
    tail := '/chat/completions';
  if LowerCase(Copy(b, Length(b) - Length(tail) + 1, Length(tail))) = tail then
    Result := b
  else
    Result := b + tail;
end;

function TbRequestHeaders(const AProfile: TTbAiProfile; const AKey: string): TStringArray;
var
  n: Integer;

  procedure Add(const S: string);
  begin
    SetLength(Result, n + 1);
    Result[n] := S;
    Inc(n);
  end;

begin
  Result := nil;
  n := 0;
  Add('Content-Type: application/json');
  Add('Accept: text/event-stream');
  if AProfile.Format = tafAnthropic then
  begin
    { always sent: Anthropic has no keyless use, and a 401 says so better than we could }
    Add('x-api-key: ' + AKey);
    Add('anthropic-version: 2023-06-01');
  end
  else if AKey <> '' then
    Add('Authorization: Bearer ' + AKey);
end;

function TbRequestBody(const AProfile: TTbAiProfile; const ASystem: string;
  const AMessages: TTbChatMessages): RawByteString;
var
  obj, msg: TJSONObject;
  arr: TJSONArray;
  i, maxOut: Integer;
  role: string;
begin
  obj := TJSONObject.Create;
  try
    obj.Add('model', AProfile.Model);
    arr := TJSONArray.Create;
    if AProfile.Format = tafOpenAI then
    begin
      msg := TJSONObject.Create;
      msg.Add('role', 'system');
      msg.Add('content', ASystem);
      arr.Add(msg);
    end;
    for i := 0 to High(AMessages) do
    begin
      if AMessages[i].Role = tcrAssistant then role := 'assistant' else role := 'user';
      msg := TJSONObject.Create;
      msg.Add('role', role);
      msg.Add('content', AMessages[i].Text);
      arr.Add(msg);
    end;
    if AProfile.Format = tafAnthropic then
    begin
      maxOut := AProfile.MaxOutput;
      if maxOut <= 0 then
        maxOut := TbAnthropicDefaultMaxOutput;
      obj.Add('max_tokens', maxOut);
      obj.Add('system', ASystem);
    end
    else if AProfile.MaxOutput > 0 then
      obj.Add('max_tokens', AProfile.MaxOutput);
    obj.Add('messages', arr);
    obj.Add('stream', True);
    Result := obj.AsJSON;
  finally
    obj.Free;
  end;
end;

{ ---- reading JSON without raising ---- }

function HexValue(const S: string; AFrom: Integer; out AValue: Integer): Boolean;
var
  i: Integer;
  c: Char;
begin
  AValue := 0;
  Result := AFrom + 3 <= Length(S);
  if not Result then Exit;
  for i := AFrom to AFrom + 3 do
  begin
    c := S[i];
    case c of
      '0'..'9': AValue := AValue * 16 + Ord(c) - Ord('0');
      'a'..'f': AValue := AValue * 16 + Ord(c) - Ord('a') + 10;
      'A'..'F': AValue := AValue * 16 + Ord(c) - Ord('A') + 10;
    else
      Exit(False);
    end;
  end;
end;

function Utf8Of(ACode: Cardinal): RawByteString;
begin
  if ACode < $80 then
    Result := Chr(ACode)
  else if ACode < $800 then
    Result := Chr($C0 or (ACode shr 6)) + Chr($80 or (ACode and $3F))
  else if ACode < $10000 then
    Result := Chr($E0 or (ACode shr 12)) + Chr($80 or ((ACode shr 6) and $3F)) +
      Chr($80 or (ACode and $3F))
  else
    Result := Chr($F0 or (ACode shr 18)) + Chr($80 or ((ACode shr 12) and $3F)) +
      Chr($80 or ((ACode shr 6) and $3F)) + Chr($80 or (ACode and $3F));
end;

{ Unicode escapes turned into the UTF-8 they stand for before fpjson sees the text: FPC
  3.2.2's scanner takes any two such escapes in a row for a surrogate pair, so the second of
  two plain characters written that way (Python's ensure_ascii writes Chinese like that)
  came out wrong. A real pair is joined here; a quote, a backslash and the control
  characters stay escaped (they mean something to the parser). }
function DecodeUnicodeEscapes(const S: string): RawByteString;
const
  cBackslash = #92;
var
  i, n, code, low: Integer;
begin
  if Pos(cBackslash + 'u', S) = 0 then
    Exit(S);
  Result := '';
  i := 1;
  n := Length(S);
  while i <= n do
  begin
    if (S[i] = cBackslash) and (i < n) then
    begin
      if (S[i + 1] = 'u') and HexValue(S, i + 2, code) and (code >= $20) and (code <> $22) and
         (code <> $5C) then
      begin
        Inc(i, 6);
        if (code >= $D800) and (code <= $DBFF) then
        begin
          if (i + 5 <= n) and (S[i] = cBackslash) and (S[i + 1] = 'u') and
             HexValue(S, i + 2, low) and (low >= $DC00) and (low <= $DFFF) then
          begin
            Inc(i, 6);
            code := $10000 + ((code - $D800) shl 10) + (low - $DC00);
          end
          else
            code := $FFFD;
        end
        else if (code >= $DC00) and (code <= $DFFF) then
          code := $FFFD;
        Result := Result + Utf8Of(code);
        Continue;
      end;
      Result := Result + S[i] + S[i + 1];   { any other escape stays as it is }
      Inc(i, 2);
      Continue;
    end;
    Result := Result + S[i];
    Inc(i);
  end;
end;

function ParseObject(const S: string): TJSONObject;
var
  d: TJSONData;
begin
  Result := nil;
  try
    d := GetJSON(DecodeUnicodeEscapes(S), True);
  except
    Exit;
  end;
  if d is TJSONObject then
    Result := TJSONObject(d)
  else
    d.Free;
end;

function ObjAt(AObj: TJSONObject; const AName: string): TJSONObject;
var
  d: TJSONData;
begin
  Result := nil;
  if AObj = nil then Exit;
  d := AObj.Find(AName);
  if d is TJSONObject then
    Result := TJSONObject(d);
end;

function StrAt(AObj: TJSONObject; const AName: string): string;
var
  d: TJSONData;
begin
  Result := '';
  if AObj = nil then Exit;
  d := AObj.Find(AName);
  if (d <> nil) and (d.JSONType = jtString) then
    Result := d.AsString;
end;

function FirstChoice(AObj: TJSONObject): TJSONObject;
var
  d: TJSONData;
begin
  Result := nil;
  if AObj = nil then Exit;
  d := AObj.Find('choices');
  if (d is TJSONArray) and (TJSONArray(d).Count > 0) and (TJSONArray(d).Items[0] is TJSONObject) then
    Result := TJSONObject(TJSONArray(d).Items[0]);
end;

{ the "error" member: an object's message (or type), or the string itself }
function ErrorText(AObj: TJSONObject; out AText: string): Boolean;
var
  d: TJSONData;
begin
  AText := '';
  Result := False;
  if AObj = nil then Exit;
  d := AObj.Find('error');
  if d = nil then Exit;
  if d is TJSONObject then
  begin
    AText := StrAt(TJSONObject(d), 'message');
    if AText = '' then
      AText := StrAt(TJSONObject(d), 'type');
    Result := True;
  end
  else if d.JSONType = jtString then
  begin
    AText := d.AsString;
    Result := True;
  end;
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

function TbParseStreamEvent(AFormat: TTbAiFormat; const AEvent: TTbSseEvent): TTbStreamDelta;
var
  obj, choice, delta, block: TJSONObject;
  kind, s, err: string;
begin
  Result := Default(TTbStreamDelta);
  if (AFormat = tafOpenAI) and (Trim(AEvent.Data) = '[DONE]') then
  begin
    Result.Kind := tspDone;
    Result.Ends := tspDone;
    Exit;
  end;
  obj := ParseObject(AEvent.Data);
  if obj = nil then
  begin
    { a heartbeat some services and proxies send ("data: ping", "data:"): ignored -- a
      reply made only of such events is not in the expected format (tbaiclient) }
    Result.NotJson := True;
    Exit;
  end;
  try
    if AFormat = tafOpenAI then
    begin
      if ErrorText(obj, err) then
      begin
        Result.Kind := tspError;
        Result.Text := err;
        Exit;
      end;
      choice := FirstChoice(obj);
      if choice = nil then Exit;
      s := StrAt(choice, 'finish_reason');
      if s = 'length' then
        Result.Ends := tspTruncated
      else if s = 'content_filter' then
        Result.Ends := tspRefused
      else if s <> '' then
        Result.Ends := tspDone;
      delta := ObjAt(choice, 'delta');
      s := StrAt(delta, 'content');
      if s <> '' then
      begin
        Result.Kind := tspText;
        Result.Text := s;
      end
      else if StrAt(delta, 'reasoning_content') <> '' then
        Result.Kind := tspThinking
      else
        Result.Kind := Result.Ends;
    end
    else
    begin
      kind := AEvent.Name;
      if (kind = '') or (kind = 'message') then
        kind := StrAt(obj, 'type');
      if kind = 'content_block_delta' then
      begin
        delta := ObjAt(obj, 'delta');
        s := StrAt(delta, 'type');
        if s = 'text_delta' then
        begin
          Result.Text := StrAt(delta, 'text');
          if Result.Text <> '' then
            Result.Kind := tspText;
        end
        else if (s = 'thinking_delta') or (s = 'signature_delta') then
          Result.Kind := tspThinking;
      end
      else if kind = 'content_block_start' then
      begin
        block := ObjAt(obj, 'content_block');
        s := StrAt(block, 'type');
        if (s = 'thinking') or (s = 'redacted_thinking') then
          Result.Kind := tspThinking
        else if (s = 'text') and (StrAt(block, 'text') <> '') then
        begin
          Result.Kind := tspText;
          Result.Text := StrAt(block, 'text');
        end;
      end
      else if kind = 'message_delta' then
      begin
        s := StrAt(ObjAt(obj, 'delta'), 'stop_reason');
        if s = 'max_tokens' then
          Result.Kind := tspTruncated
        else if s = 'refusal' then
          Result.Kind := tspRefused;
        Result.Ends := Result.Kind;
      end
      else if kind = 'message_stop' then
      begin
        Result.Kind := tspDone;
        Result.Ends := tspDone;
      end
      else if kind = 'error' then
      begin
        Result.Kind := tspError;
        if not ErrorText(obj, Result.Text) or (Result.Text = '') then
          Result.Text := 'error';
      end;
      { ping, message_start, content_block_stop, anything else: nothing }
    end;
  finally
    obj.Free;
  end;
end;

function TbParseWholeReply(AFormat: TTbAiFormat; const ABody: string; out AText: string): Boolean;
var
  obj, choice, item: TJSONObject;
  d: TJSONData;
  i: Integer;
  found: Boolean;
begin
  AText := '';
  Result := False;
  obj := ParseObject(ABody);
  if obj = nil then Exit;
  try
    found := False;
    if AFormat = tafOpenAI then
    begin
      choice := FirstChoice(obj);
      d := nil;
      if ObjAt(choice, 'message') <> nil then
        d := ObjAt(choice, 'message').Find('content');
      if (d <> nil) and (d.JSONType = jtString) then
      begin
        AText := d.AsString;
        found := True;
      end;
    end
    else
    begin
      d := obj.Find('content');
      if d is TJSONArray then
        for i := 0 to TJSONArray(d).Count - 1 do
          if TJSONArray(d).Items[i] is TJSONObject then
          begin
            item := TJSONObject(TJSONArray(d).Items[i]);
            if StrAt(item, 'type') = 'text' then
            begin
              AText := AText + StrAt(item, 'text');
              found := True;
            end;
          end;
    end;
    Result := found;
  finally
    obj.Free;
  end;
end;

function TbErrorBodyMessage(const ABody: string): string;
var
  obj: TJSONObject;
begin
  Result := '';
  if Trim(ABody) = '' then Exit;
  obj := ParseObject(ABody);
  if obj = nil then
    Exit(Trim(Copy(StripControls(ABody), 1, 200)));
  try
    if not ErrorText(obj, Result) then
      Result := StrAt(obj, 'message');
  finally
    obj.Free;
  end;
end;

end.
