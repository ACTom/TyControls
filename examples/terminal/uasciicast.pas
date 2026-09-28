unit uasciicast;

{ A reader for asciicast v2 recordings (https://docs.asciinema.org/manual/asciicast/v2/),
  private to the terminal example. The first line is a JSON header -- version (must be
  2), width, height; every other non-empty line is [time, type, data]. Only "o" (output)
  events are kept; "i" (input) and anything else are skipped.

  Known limit: fpjson drops a \u0000 escape, so an output event carrying NUL loses those
  bytes. The recordings shipped with the example have none (a release test checks it). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, jsonparser;

type
  TAsciicastEvent = record
    Time: Double;          { seconds from the start }
    Data: RawByteString;   { UTF-8, as the program wrote it }
  end;

  TAsciicast = class
  private
    FEvents: array of TAsciicastEvent;
    FCount: Integer;
    FWidth, FHeight: Integer;
    FFileName: string;
    function GetEvent(AIndex: Integer): TAsciicastEvent;
  public
    { raises an Exception naming the file when it is not an asciicast v2 recording }
    procedure LoadFromFile(const AFileName: string);
    property Width: Integer read FWidth;
    property Height: Integer read FHeight;
    property Count: Integer read FCount;
    property Events[AIndex: Integer]: TAsciicastEvent read GetEvent; default;
    property FileName: string read FFileName;
  end;

implementation

resourcestring
  rsNotV2 = '%s is not an asciicast v2 recording';

function TAsciicast.GetEvent(AIndex: Integer): TAsciicastEvent;
begin
  Result := FEvents[AIndex];
end;

procedure TAsciicast.LoadFromFile(const AFileName: string);
var
  lines: TStringList;
  i: Integer;
  head, row: TJSONData;
  arr: TJSONArray;
begin
  FCount := 0;
  FEvents := nil;
  FWidth := 80;
  FHeight := 24;
  FFileName := AFileName;
  lines := TStringList.Create;
  try
    lines.LoadFromFile(AFileName);
    if lines.Count = 0 then
      raise Exception.CreateFmt(rsNotV2, [ExtractFileName(AFileName)]);
    head := GetJSON(lines[0]);
    try
      if not (head is TJSONObject) or (TJSONObject(head).Get('version', 0) <> 2) then
        raise Exception.CreateFmt(rsNotV2, [ExtractFileName(AFileName)]);
      FWidth := TJSONObject(head).Get('width', 80);
      FHeight := TJSONObject(head).Get('height', 24);
    finally
      head.Free;
    end;
    SetLength(FEvents, lines.Count);
    for i := 1 to lines.Count - 1 do
    begin
      if Trim(lines[i]) = '' then Continue;
      row := GetJSON(lines[i]);
      try
        if not (row is TJSONArray) then Continue;
        arr := TJSONArray(row);
        if (arr.Count < 3) or (arr.Strings[1] <> 'o') then Continue;
        FEvents[FCount].Time := arr.Floats[0];
        FEvents[FCount].Data := RawByteString(arr.Strings[2]);   { fpjson hands back UTF-8 }
        Inc(FCount);
      finally
        row.Free;
      end;
    end;
    SetLength(FEvents, FCount);
  finally
    lines.Free;
  end;
end;

end.
