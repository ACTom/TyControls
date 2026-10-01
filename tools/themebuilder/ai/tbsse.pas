unit tbsse;
{ A server-sent events reader (the WHATWG event stream rules), fed the bytes as the network
  hands them over -- a chunk may end anywhere: in the middle of a line, of a UTF-8
  character, between the CR and the LF of a line break.

    - a line ends with CRLF, LF or CR; a CR at the very end of a chunk waits for the next
      byte to tell whether an LF follows
    - a byte order mark at the very start of the stream is dropped (only there)
    - a line starting with ':' is a comment
    - "field: value": one space after the colon is dropped; a line with no colon is a field
      with an empty value
    - data lines are joined with LF; event sets the event's name (default "message");
      id, retry and unknown fields are ignored
    - a blank line dispatches the event (nothing when no data line came)
    - at the end of the stream, an event still waiting for its blank line is dropped

  No LCL: the WSL console program compiles it too. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils;

type
  TTbSseEvent = record
    Name: string;                 { 'message' when the event has no event: line }
    Data: string;                 { data: lines joined with #10 }
  end;
  TTbSseEventProc = procedure(const AEvent: TTbSseEvent) of object;

  TTbSseParser = class
  private
    FOnEvent: TTbSseEventProc;
    FLine: RawByteString;         { the line not finished yet }
    FPendingCR: Boolean;          { the last chunk ended with a CR }
    FData: RawByteString;
    FHasData: Boolean;
    FName: string;
    FStarted: Boolean;            { the BOM goes at the very start only }
    FHead: RawByteString;         { the first bytes, until it is clear whether they are a BOM }
    FEventCount: Integer;
    FDroppedPartial: Boolean;
    procedure HandleLine(const ALine: RawByteString);
    procedure DispatchEvent;
    procedure FeedBytes(const AChunk: RawByteString);
  public
    constructor Create(AOnEvent: TTbSseEventProc);
    procedure Feed(const AChunk: RawByteString);
    procedure Finish;             { a last event without its blank line is dropped }
    property EventCount: Integer read FEventCount;
    property DroppedPartial: Boolean read FDroppedPartial;
  end;

implementation

const
  cBom = #$EF#$BB#$BF;

constructor TTbSseParser.Create(AOnEvent: TTbSseEventProc);
begin
  inherited Create;
  FOnEvent := AOnEvent;
end;

procedure TTbSseParser.DispatchEvent;
var
  ev: TTbSseEvent;
begin
  if FHasData then
  begin
    ev.Data := FData;
    if (ev.Data <> '') and (ev.Data[Length(ev.Data)] = #10) then
      SetLength(ev.Data, Length(ev.Data) - 1);
    if FName = '' then
      ev.Name := 'message'
    else
      ev.Name := FName;
    Inc(FEventCount);
    if Assigned(FOnEvent) then
      FOnEvent(ev);
  end;
  FData := '';
  FHasData := False;
  FName := '';
end;

procedure TTbSseParser.HandleLine(const ALine: RawByteString);
var
  p: Integer;
  field, value: RawByteString;
begin
  if ALine = '' then
  begin
    DispatchEvent;
    Exit;
  end;
  if ALine[1] = ':' then
    Exit;                                   { a comment }
  p := Pos(':', ALine);
  if p = 0 then
  begin
    field := ALine;
    value := '';
  end
  else
  begin
    field := Copy(ALine, 1, p - 1);
    value := Copy(ALine, p + 1, MaxInt);
    if (value <> '') and (value[1] = ' ') then
      Delete(value, 1, 1);
  end;
  if field = 'data' then
  begin
    FData := FData + value + #10;
    FHasData := True;
  end
  else if field = 'event' then
    FName := value;
  { id, retry, anything else: ignored }
end;

procedure TTbSseParser.Feed(const AChunk: RawByteString);
var
  s: RawByteString;
begin
  s := AChunk;
  if not FStarted then
  begin
    { the BOM may itself come in pieces: wait until three bytes, or one that is not it }
    FHead := FHead + s;
    if (Length(FHead) < 3) and (FHead = Copy(cBom, 1, Length(FHead))) then
      Exit;
    FStarted := True;
    s := FHead;
    FHead := '';
    if Copy(s, 1, 3) = cBom then
      Delete(s, 1, 3);
  end;
  FeedBytes(s);
end;

procedure TTbSseParser.FeedBytes(const AChunk: RawByteString);
var
  i, start: Integer;
  c: Char;
  s: RawByteString;
begin
  s := AChunk;
  i := 1;
  if FPendingCR and (s <> '') then
  begin
    FPendingCR := False;
    if s[1] = #10 then
      i := 2;                               { the LF of a CRLF split across chunks }
  end;
  start := i;
  while i <= Length(s) do
  begin
    c := s[i];
    if (c = #13) or (c = #10) then
    begin
      FLine := FLine + Copy(s, start, i - start);
      HandleLine(FLine);
      FLine := '';
      if c = #13 then
      begin
        if i = Length(s) then
          FPendingCR := True
        else if s[i + 1] = #10 then
          Inc(i);
      end;
      start := i + 1;
    end;
    Inc(i);
  end;
  FLine := FLine + Copy(s, start, MaxInt);
end;

procedure TTbSseParser.Finish;
begin
  if not FStarted then
  begin
    FStarted := True;
    FeedBytes(FHead);                       { fewer bytes than a BOM, and all of a BOM's }
    FHead := '';
  end;
  if FLine <> '' then
  begin
    HandleLine(FLine);                      { the last line had no break after it }
    FLine := '';
  end;
  FPendingCR := False;
  if FHasData then
  begin
    FDroppedPartial := True;
    FData := '';
    FHasData := False;
    FName := '';
  end;
end;

end.
