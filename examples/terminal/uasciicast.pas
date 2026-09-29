unit uasciicast;

{ A reader for asciicast v2 recordings (https://docs.asciinema.org/manual/asciicast/v2/),
  private to the terminal example, and the player that feeds one to a terminal. The
  first line is a JSON header -- version (must be 2), width, height, optionally
  idle_time_limit; every other non-empty line is [time, type, data]. Only "o" (output)
  events are kept; "i" (input) and anything else are skipped.

  The player writes with flow control: at most one chunk is in the terminal's queue at
  a time. It hands the chunk to OnWrite with a tag and waits for ChunkDone(tag) -- the
  terminal's write callback -- before it writes the next. "All at once" therefore goes
  out in chunks of up to MaxChunkBytes, never faster than the terminal parses, and a
  big recording cannot overflow the terminal's queue (ETyTerminalWriteOverflow). A
  callback that belongs to an earlier Rewind carries an old tag and is ignored.

  Known limit: fpjson drops a \u0000 escape, so an output event carrying NUL loses those
  bytes. The recordings shipped with the example have none (a release test checks it). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, fpjson, jsonparser;

const
  { what a sane recording's grid can be: a header outside this is clamped }
  AsciicastMinWidth = 2;
  AsciicastMaxWidth = 500;
  AsciicastMinHeight = 1;
  AsciicastMaxHeight = 300;

type
  TAsciicastEvent = record
    Time: Double;          { seconds from the start, idle_time_limit applied }
    Data: RawByteString;   { UTF-8, as the program wrote it }
  end;

  TAsciicast = class
  private
    FEvents: array of TAsciicastEvent;
    FCount: Integer;
    FWidth, FHeight: Integer;
    FIdleTimeLimit: Double;
    FFileName: string;
    function GetEvent(AIndex: Integer): TAsciicastEvent;
  public
    { Raises an Exception naming the file when it is not an asciicast v2 recording;
      then nothing changes -- the recording loaded before stays as it was. }
    procedure LoadFromFile(const AFileName: string);
    procedure LoadFromStrings(ALines: TStrings; const AFileName: string);
    property Width: Integer read FWidth;
    property Height: Integer read FHeight;
    property IdleTimeLimit: Double read FIdleTimeLimit;   { 0 = none }
    property Count: Integer read FCount;
    property Events[AIndex: Integer]: TAsciicastEvent read GetEvent; default;
    property FileName: string read FFileName;
  end;

  TAsciicastWriteEvent = procedure(Sender: TObject; const AData: RawByteString; ATag: PtrInt) of object;

  { Plays a recording into OnWrite, one chunk in flight at a time (see the unit header). }
  TAsciicastPlayer = class
  private
    FCast: TAsciicast;
    FNext: Integer;
    FPlayedMs: Double;
    FInFlight: Boolean;
    FGeneration: PtrInt;
    FMaxChunkBytes: Integer;
    FOnWrite: TAsciicastWriteEvent;
    procedure Send(AUntil: Integer);
  public
    constructor Create(ACast: TAsciicast);
    { back to the start of the recording; a chunk still in flight is forgotten }
    procedure Rewind;
    { AElapsedMs of wall time at ASpeed (1 = as recorded); ASpeed < 0 = all at once }
    procedure Advance(AElapsedMs, ASpeed: Double);
    { the next event alone }
    procedure Step;
    { the terminal is done with the chunk tagged ATag }
    procedure ChunkDone(ATag: PtrInt);
    function Finished: Boolean;
    property Next: Integer read FNext;
    property InFlight: Boolean read FInFlight;
    property PlayedMs: Double read FPlayedMs;
    property MaxChunkBytes: Integer read FMaxChunkBytes write FMaxChunkBytes;
    property OnWrite: TAsciicastWriteEvent read FOnWrite write FOnWrite;
  end;

implementation

resourcestring
  rsNotV2 = '%s is not an asciicast v2 recording';

{ ---- TAsciicast ---- }

function TAsciicast.GetEvent(AIndex: Integer): TAsciicastEvent;
begin
  Result := FEvents[AIndex];
end;

procedure TAsciicast.LoadFromFile(const AFileName: string);
var
  lines: TStringList;
begin
  lines := TStringList.Create;
  try
    lines.LoadFromFile(AFileName);
    LoadFromStrings(lines, AFileName);
  finally
    lines.Free;
  end;
end;

procedure TAsciicast.LoadFromStrings(ALines: TStrings; const AFileName: string);
var
  i, n, w, h: Integer;
  head, row: TJSONData;
  arr: TJSONArray;
  evs: array of TAsciicastEvent;
  idle, t, prev, shift: Double;
begin
  { everything into locals first: a file that fails half-way leaves the recording loaded
    before untouched }
  if ALines.Count = 0 then
    raise Exception.CreateFmt(rsNotV2, [ExtractFileName(AFileName)]);
  head := nil;
  try
    try
      head := GetJSON(ALines[0]);
    except
      on E: Exception do
        raise Exception.CreateFmt(rsNotV2, [ExtractFileName(AFileName)]);
    end;
    if not (head is TJSONObject) or (TJSONObject(head).Get('version', 0) <> 2) then
      raise Exception.CreateFmt(rsNotV2, [ExtractFileName(AFileName)]);
    w := EnsureRange(TJSONObject(head).Get('width', 80), AsciicastMinWidth, AsciicastMaxWidth);
    h := EnsureRange(TJSONObject(head).Get('height', 24), AsciicastMinHeight, AsciicastMaxHeight);
    idle := TJSONObject(head).Get('idle_time_limit', 0.0);
    if not (idle > 0) then idle := 0;
  finally
    head.Free;
  end;
  evs := nil;
  SetLength(evs, ALines.Count);
  n := 0;
  prev := 0;
  shift := 0;
  for i := 1 to ALines.Count - 1 do
  begin
    if Trim(ALines[i]) = '' then Continue;
    try
      row := GetJSON(ALines[i]);
    except
      on E: Exception do
        raise Exception.CreateFmt(rsNotV2, [ExtractFileName(AFileName)]);
    end;
    try
      if not (row is TJSONArray) then Continue;
      arr := TJSONArray(row);
      if (arr.Count < 3) or (arr.Types[0] <> jtNumber) or (arr.Types[2] <> jtString) then Continue;
      t := arr.Floats[0];
      { idle_time_limit: a pause longer than the limit plays as the limit (asciinema's
        own reading of the header field); the shift carries on to every later event }
      if (idle > 0) and (t - prev > idle) then
        shift := shift + (t - prev - idle);
      prev := Max(prev, t);
      if arr.Strings[1] <> 'o' then Continue;
      evs[n].Time := t - shift;
      evs[n].Data := RawByteString(arr.Strings[2]);   { fpjson hands back UTF-8 }
      Inc(n);
    finally
      row.Free;
    end;
  end;
  SetLength(evs, n);
  { it read: now it replaces the old one }
  FEvents := evs;
  FCount := n;
  FWidth := w;
  FHeight := h;
  FIdleTimeLimit := idle;
  FFileName := AFileName;
end;

{ ---- TAsciicastPlayer ---- }

constructor TAsciicastPlayer.Create(ACast: TAsciicast);
begin
  inherited Create;
  FCast := ACast;
  FMaxChunkBytes := 64 * 1024;
end;

procedure TAsciicastPlayer.Rewind;
begin
  FNext := 0;
  FPlayedMs := 0;
  FInFlight := False;
  Inc(FGeneration);
end;

function TAsciicastPlayer.Finished: Boolean;
begin
  Result := FNext >= FCast.Count;
end;

{ events FNext .. AUntil - 1 as one chunk, cut at MaxChunkBytes }
procedure TAsciicastPlayer.Send(AUntil: Integer);
var
  chunk: RawByteString;
  last: Integer;
begin
  if FInFlight or (FNext >= AUntil) then Exit;
  chunk := '';
  last := FNext;
  repeat
    chunk := chunk + FCast[last].Data;
    Inc(last);
  until (last >= AUntil) or (Length(chunk) >= FMaxChunkBytes);
  FPlayedMs := Max(FPlayedMs, FCast[last - 1].Time * 1000);
  FNext := last;
  FInFlight := True;
  if Assigned(FOnWrite) then
    FOnWrite(Self, chunk, FGeneration);
end;

procedure TAsciicastPlayer.Advance(AElapsedMs, ASpeed: Double);
var
  due: Integer;
begin
  if ASpeed < 0 then
  begin
    Send(FCast.Count);
    Exit;
  end;
  FPlayedMs := FPlayedMs + AElapsedMs * ASpeed;
  { still in flight: the events that fall due wait for the next chunk }
  if FInFlight then Exit;
  due := FNext;
  while (due < FCast.Count) and (FCast[due].Time * 1000 <= FPlayedMs) do
    Inc(due);
  Send(due);
end;

procedure TAsciicastPlayer.Step;
begin
  if FNext < FCast.Count then
    Send(FNext + 1);
end;

procedure TAsciicastPlayer.ChunkDone(ATag: PtrInt);
begin
  if ATag = FGeneration then
    FInFlight := False;
end;

end.
