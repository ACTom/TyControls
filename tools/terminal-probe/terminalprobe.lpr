program terminalprobe;
{$mode objfpc}{$H+}
{$APPTYPE CONSOLE}
{ Feeds a recording or any byte file to TTyTerminalCore and prints the screen, for
  eyeballing against a real terminal (design spec 18). Builds from source/ without
  the package and uses no LCL unit.

    terminalprobe <file> [--cols N] [--rows N] [--scrollback N]
                  [--unicode 6|11|15|15-graphemes] [--convert-eol]
                  [--scrollback-too] [--chunk N]

  <file> is an asciicast v2 recording (.cast: the size from its header, the "o"
  events joined) or any file, taken as raw bytes. Default size 80 x 24. --chunk N
  writes N bytes at a time through the queue and runs ProcessPending until it
  answers False (the scheduling path); otherwise one WriteSync. Prints one status
  line, then the viewport (with --scrollback-too the scrollback first), one row
  per line as "NN|text", then the first 64 bytes the core sent back. }

uses
  SysUtils, Classes, fpjson, jsonparser, tyControls.Unicode.Width, tyControls.Terminal.Parser,
  tyControls.Terminal.Buffer, tyControls.Terminal.Core;

type
  TProbeSink = class
  public
    Data: RawByteString;
    procedure OnData(Sender: TObject; const AData: RawByteString);
  end;

procedure TProbeSink.OnData(Sender: TObject; const AData: RawByteString);
begin
  Data := Data + AData;
end;

function ReadBytes(const APath: string): RawByteString;
var
  fs: TFileStream;
begin
  fs := TFileStream.Create(APath, fmOpenRead or fmShareDenyWrite);
  try
    Result := '';
    SetLength(Result, fs.Size);
    if fs.Size > 0 then
      fs.ReadBuffer(Result[1], fs.Size);
  finally
    fs.Free;
  end;
end;

{ the "o" events of an asciicast v2 file, joined; the size from its header }
function ReadCast(const AText: RawByteString; var ACols, ARows: Integer): RawByteString;
var
  lines: TStringList;
  i: Integer;
  d: TJSONData;
  arr: TJSONArray;
begin
  Result := '';
  lines := TStringList.Create;
  try
    lines.Text := AText;
    for i := 0 to lines.Count - 1 do
    begin
      if Trim(lines[i]) = '' then
        Continue;
      d := GetJSON(lines[i]);
      try
        if (i = 0) and (d is TJSONObject) then
        begin
          ACols := TJSONObject(d).Get('width', ACols);
          ARows := TJSONObject(d).Get('height', ARows);
        end
        else if d is TJSONArray then
        begin
          arr := TJSONArray(d);
          if (arr.Count >= 3) and (arr.Strings[1] = 'o') then
            Result := Result + arr.Strings[2];
        end;
      finally
        d.Free;
      end;
    end;
  finally
    lines.Free;
  end;
end;

function Hex(const S: RawByteString; AMax: Integer): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do
  begin
    if i > AMax then
    begin
      Result := Result + '...';
      Break;
    end;
    Result := Result + IntToHex(Ord(S[i]), 2) + ' ';
  end;
  Result := Trim(Result);
end;

{ a whole number for an option, or a message and exit code 1 }
function IntArg(const AName, AValue: string; AMin: Integer): Integer;
begin
  if not TryStrToInt(AValue, Result) or (Result < AMin) then
  begin
    WriteLn(Format('%s wants a whole number of at least %d, not "%s"', [AName, AMin, AValue]));
    Halt(1);
  end;
end;

var
  path, arg, act: string;
  cols, rows, scrollback, chunk, i, k: Integer;
  convertEol, scrollbackToo, isCast, known: Boolean;
  version: TTyUnicodeVersion;
  input: RawByteString;
  core: TTyTerminalCore;
  sink: TProbeSink;
  buf: TTyTerminalBuffer;
  v: TTyUnicodeVersion;
begin
  if ParamCount < 1 then
  begin
    WriteLn('usage: terminalprobe <file> [--cols N] [--rows N] [--scrollback N] [--unicode 6|11|15|15-graphemes]');
    WriteLn('                     [--convert-eol] [--scrollback-too] [--chunk N]');
    Halt(1);
  end;
  path := ParamStr(1);
  cols := -1;
  rows := -1;
  scrollback := 1000;
  chunk := 0;
  convertEol := False;
  scrollbackToo := False;
  version := tuv11;
  i := 2;
  while i <= ParamCount do
  begin
    arg := ParamStr(i);
    if arg = '--convert-eol' then convertEol := True
    else if arg = '--scrollback-too' then scrollbackToo := True
    else if (i < ParamCount) and ((arg = '--cols') or (arg = '--rows') or (arg = '--scrollback')
      or (arg = '--chunk') or (arg = '--unicode')) then
    begin
      Inc(i);
      if arg = '--cols' then cols := IntArg(arg, ParamStr(i), 1)
      else if arg = '--rows' then rows := IntArg(arg, ParamStr(i), 1)
      else if arg = '--scrollback' then scrollback := IntArg(arg, ParamStr(i), 0)
      else if arg = '--chunk' then chunk := IntArg(arg, ParamStr(i), 1)
      else
      begin
        known := False;
        for v := Low(TTyUnicodeVersion) to High(TTyUnicodeVersion) do
          if TyUnicodeVersionName(v) = ParamStr(i) then
          begin
            version := v;
            known := True;
          end;
        if not known then
        begin
          WriteLn('--unicode wants 6, 11, 15 or 15-graphemes, not "', ParamStr(i), '"');
          Halt(1);
        end;
      end;
    end
    else
    begin
      WriteLn('unknown argument: ', arg);
      Halt(1);
    end;
    Inc(i);
  end;
  try
    input := ReadBytes(path);
  except
    on E: Exception do
    begin
      WriteLn('cannot read ', path, ': ', E.Message);
      Halt(1);
    end;
  end;
  isCast := LowerCase(ExtractFileExt(path)) = '.cast';
  k := 80;
  i := 24;
  if isCast then
    input := ReadCast(input, k, i);
  if cols < 0 then cols := k;
  if rows < 0 then rows := i;

  sink := TProbeSink.Create;
  core := TTyTerminalCore.Create(cols, rows);
  try
    core.OnData := @sink.OnData;
    core.Scrollback := scrollback;
    core.ConvertEol := convertEol;
    core.UnicodeVersion := version;
    if chunk > 0 then
    begin
      k := 1;
      while k <= Length(input) do
      begin
        core.Write(Copy(input, k, chunk));
        Inc(k, chunk);
      end;
      while core.ProcessPending do ;
    end
    else
      core.WriteSync(input);
    buf := core.Buffer;
    if core.Buffers.IsAlt then act := 'alt' else act := 'normal';
    WriteLn(Format('%d x %d, ybase %d, cursor (%d, %d), active %s, title "%s"',
      [core.Cols, core.Rows, buf.YBase, buf.X, buf.Y, act, core.Title]));
    if scrollbackToo then
      for k := 0 to buf.YBase - 1 do
        WriteLn(Format('S%.3d|%s', [k, buf.TranslateBufferLineToString(k, True, 0, buf.Lines.Get(k).Length)]));
    for k := 0 to core.Rows - 1 do
      if buf.YDisp + k < buf.Lines.Length then
        WriteLn(Format('%.2d|%s', [k, buf.TranslateBufferLineToString(buf.YDisp + k, True, 0,
          buf.Lines.Get(buf.YDisp + k).Length)]));
    WriteLn('OnData: ', Hex(sink.Data, 64));
  finally
    core.Free;
    sink.Free;
  end;
end.
