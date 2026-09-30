program zmprobe;

{ Phase 7, Task 0 (spec 19.2 item 12): does a byte survive the trip between the
  terminal example and a WSL program? Windows console program, no LCL; it runs the
  example's session (examples/terminal/uptysession + uptywin).

    zmprobe --conpty-out   through ConPTY, program -> us: bytes 0..255 four times
    zmprobe --conpty-in    through ConPTY, us -> program: bytes 0..255 four times,
                           read back through od
    zmprobe --conpty-in-printable
                           the same without the C0 controls ($20..$FF four times)
    zmprobe --conpty-sz    through ConPTY: the head of an sz session (4 KB file)
    zmprobe --pipe-out     as --conpty-out, on two plain pipes (no pseudo console)
    zmprobe --pipe-in      as --conpty-in, on two plain pipes

  Each prints what arrived and, for every byte value that did not arrive as sent, what
  became of it. Exit code 0 = everything as sent, 1 = not, 2 = could not run.

  Built by hand, like tools/terminal-conpty-record:

    cd tools/terminal-zmodem-probe && mkdir -p lib && \
      fpc -Mobjfpc -Sh -FUlib -Fu../../examples/terminal zmprobe.lpr }

{$mode objfpc}{$H+}

uses
  Windows, Classes, SysUtils, SyncObjs, uptysession, uptywin;

type
  TWaker = class
  public
    Event: TEvent;
    constructor Create;
    destructor Destroy; override;
    procedure Wake(Sender: TObject);
  end;

constructor TWaker.Create;
begin
  inherited Create;
  Event := TEvent.Create(nil, False, False, '');
end;

destructor TWaker.Destroy;
begin
  Event.Free;
  inherited Destroy;
end;

procedure TWaker.Wake(Sender: TObject);
begin
  Event.SetEvent;
end;

const
  OutCmd = 'wsl.exe -d Ubuntu -- python3 -c "import sys; sys.stdout.buffer.write(bytes(range(256))*4); sys.stdout.flush()"';
  { timeout: if some bytes are lost the program never gets 1024 and would wait for
    ever; --foreground, or dd is not in the terminal's foreground group and stops on
    SIGTTIN. dd bs=1 (not head): what it read is written already when timeout ends it.
    stty sane before od: raw mode also turns off LF -> CR LF, and ConPTY renders the
    staircase with cursor moves. 32 bytes a line, 32 lines: the window (Run) holds
    them without scrolling. The sleep: ConPTY renders od's output only while the
    program is still there. }
  InCmd = 'wsl.exe -d Ubuntu -- sh -c ''stty raw -echo 2>/dev/null; ' +
    'timeout --foreground 5 dd bs=1 count=1024 2>/dev/null > /tmp/zmprobe.in; stty sane 2>/dev/null; ' +
    'od -An -tx1 -v -w32 /tmp/zmprobe.in; rm -f /tmp/zmprobe.in; sleep 1''';

var
  PipeProcess: THandle = 0;

{ the minimal pipe backend (Task 9 builds the real one): a process on two anonymous
  pipes, stderr on the output pipe }
function StartOnPipes(const ACommand: string; out ABackend: TPtyBackend): Boolean;
var
  sa: TSecurityAttributes;
  inRead, inWrite, outRead, outWrite: THandle;
  si: TStartupInfoW;
  pi: TProcessInformation;
  cmd: UnicodeString;
begin
  Result := False;
  ABackend := nil;
  FillChar(sa, SizeOf(sa), 0);
  sa.nLength := SizeOf(sa);
  sa.bInheritHandle := True;
  if not CreatePipe(inRead, inWrite, @sa, 0) then Exit;
  if not CreatePipe(outRead, outWrite, @sa, 0) then Exit;
  SetHandleInformation(inWrite, HANDLE_FLAG_INHERIT, 0);
  SetHandleInformation(outRead, HANDLE_FLAG_INHERIT, 0);
  FillChar(si, SizeOf(si), 0);
  si.cb := SizeOf(si);
  si.dwFlags := STARTF_USESTDHANDLES;
  si.hStdInput := inRead;
  si.hStdOutput := outWrite;
  si.hStdError := outWrite;
  FillChar(pi, SizeOf(pi), 0);
  cmd := UTF8Decode(ACommand);
  UniqueString(cmd);
  if not CreateProcessW(nil, PWideChar(cmd), nil, nil, True, CREATE_NO_WINDOW or CREATE_UNICODE_ENVIRONMENT,
    nil, nil, @si, @pi) then
  begin
    WriteLn('CreateProcessW: ', SysErrorMessage(GetLastError));
    Exit;
  end;
  CloseHandle(pi.hThread);
  CloseHandle(inRead);
  CloseHandle(outWrite);
  PipeProcess := pi.hProcess;
  ABackend := TPipeBackend.Create(inWrite, outRead, True);
  Result := True;
end;

function Hex(const S: RawByteString; AFrom, ACount: Integer): string;
var
  i: Integer;
begin
  Result := '';
  for i := AFrom to AFrom + ACount - 1 do
    if (i >= 1) and (i <= Length(S)) then
      Result := Result + IntToHex(Ord(S[i]), 2) + ' ';
end;

procedure DumpHex(const S: RawByteString);
var
  i: Integer;
begin
  i := 1;
  while i <= Length(S) do
  begin
    WriteLn('  ', Format('%.5d', [i - 1]), ': ', Hex(S, i, 32));
    Inc(i, 32);
  end;
end;

{ runs ACommand, writes AInput after 2 s when not empty, collects ASeconds }
function Run(APipe: Boolean; const ACommand: string; const AInput: RawByteString; ASeconds: Integer;
  out AData: RawByteString): Boolean;
var
  waker: TWaker;
  s: TPtySession;
  backend: TPtyBackend;
  err: string;
  chunk: RawByteString;
  exited, wrote: Boolean;
  code: Int64;
  t0: QWord;
begin
  Result := False;
  AData := '';
  if APipe then
  begin
    if not StartOnPipes(ACommand, backend) then Exit;
  end
  else
    backend := TConPtyBackend.Create;
  waker := TWaker.Create;
  s := TPtySession.Create(backend);
  try
    s.OnWake := @waker.Wake;
    if not s.Start(ACommand, 200, 50, err) then
    begin
      WriteLn('not started: ', err);
      Exit;
    end;
    t0 := GetTickCount64;
    wrote := AInput = '';
    while GetTickCount64 - t0 < QWord(ASeconds) * 1000 do
    begin
      waker.Event.WaitFor(50);
      if not wrote and (GetTickCount64 - t0 >= 2000) then
      begin
        s.Write(AInput);
        wrote := True;
      end;
      if s.Pump(chunk, exited, code) then
      begin
        AData := AData + chunk;
        s.Delivered(Length(chunk));
        if exited then
        begin
          WriteLn(Format('  the program ended after %d ms, exit code %d', [GetTickCount64 - t0, code]));
          Break;
        end;
      end;
    end;
    Result := True;
  finally
    s.Free;
    if PipeProcess <> 0 then
    begin
      TerminateProcess(PipeProcess, 1);
      CloseHandle(PipeProcess);
      PipeProcess := 0;
    end;
    PtyWaitForFinishers(PtyExitWaitMs);
    waker.Free;
  end;
end;

function Pattern: RawByteString;
var
  i: Integer;
begin
  SetLength(Result, 1024);
  for i := 0 to 1023 do
    Result[i + 1] := AnsiChar(i and 255);
end;

{ the table: for every byte value, how many times it was sent and how many times it
  came back; only the ones that differ. True = the whole 0..255 run arrived in order. }
function Compare(const ASent, AGot: RawByteString): Boolean;
var
  sent, got: array[0..255] of Integer;
  i, p, bad: Integer;
  run: RawByteString;
begin
  FillChar(sent, SizeOf(sent), 0);
  FillChar(got, SizeOf(got), 0);
  for i := 1 to Length(ASent) do Inc(sent[Ord(ASent[i])]);
  for i := 1 to Length(AGot) do Inc(got[Ord(AGot[i])]);
  SetLength(run, 256);
  for i := 0 to 255 do run[i + 1] := AnsiChar(i);
  Result := Pos(run, AGot) > 0;
  bad := 0;
  WriteLn('  byte  sent  got   outcome');
  for i := 0 to 255 do
    if sent[i] <> got[i] then
    begin
      Inc(bad);
      if got[i] = 0 then
        WriteLn(Format('  %.2x    %4d  %4d  lost', [i, sent[i], got[i]]))
      else if got[i] > sent[i] then
        WriteLn(Format('  %.2x    %4d  %4d  more than sent (added by the way)', [i, sent[i], got[i]]))
      else
        WriteLn(Format('  %.2x    %4d  %4d  some lost', [i, sent[i], got[i]]));
    end;
  WriteLn(Format('  %d byte values differ; received %d bytes, sent %d', [bad, Length(AGot), Length(ASent)]));
  if Result then
    WriteLn('  the run 00 01 .. ff arrived whole')
  else
  begin
    { first place where the received bytes stop following the sent ones }
    p := 1;
    i := 1;
    while (p <= Length(AGot)) and (AGot[p] <> #0) do Inc(p);
    while (p <= Length(AGot)) and (i <= Length(ASent)) and (AGot[p] = ASent[i]) do
    begin
      Inc(p);
      Inc(i);
    end;
    WriteLn(Format('  the run is not there whole; first difference at sent byte %d (value %.2x), received offset %d:',
      [i - 1, Ord(ASent[i]), p - 1]));
    WriteLn('    sent: ', Hex(ASent, i - 8, 24));
    WriteLn('    got:  ', Hex(AGot, p - 8, 24));
  end;
end;

{ od -An -tx1 output back to bytes: every token of two hex digits }
function FromOd(const AText: RawByteString): RawByteString;
var
  i: Integer;
  function IsHex(C: AnsiChar): Boolean;
  begin
    Result := C in ['0'..'9', 'a'..'f'];
  end;
begin
  Result := '';
  i := 1;
  while i <= Length(AText) - 1 do
  begin
    if IsHex(AText[i]) and IsHex(AText[i + 1]) and ((i = 1) or (AText[i - 1] = ' '))
      and ((i + 2 > Length(AText)) or (AText[i + 2] in [' ', #13, #10, #27])) then
    begin
      Result := Result + AnsiChar(StrToInt('$' + Copy(AText, i, 2)));
      Inc(i, 2);
    end
    else
      Inc(i);
  end;
end;

function DoOut(APipe: Boolean): Integer;
var
  got: RawByteString;
begin
  if not Run(APipe, OutCmd, '', 5, got) then Exit(2);
  if Compare(Pattern, got) and (Length(got) = 1024) then Result := 0 else Result := 1;
  if Result <> 0 then
  begin
    WriteLn('  the first 256 bytes received:');
    DumpHex(Copy(got, 1, 256));
  end;
end;

{ 0..255 four times, or (APrintable) only $20..$FF four times: without the C0 controls
  (Ctrl+C among them) the program is not stopped by the console, and the table shows
  what becomes of the high bytes }
function DoIn(APipe, APrintable: Boolean): Integer;
var
  got, back, sent: RawByteString;
  cmd: string;
  i: Integer;
begin
  if APrintable then
  begin
    sent := '';
    for i := 0 to 1023 do
      if (i and 255) >= $20 then
        sent := sent + AnsiChar(i and 255);
  end
  else
    sent := Pattern;
  cmd := StringReplace(InCmd, '1024', IntToStr(Length(sent)), []);
  { ZMPROBE_INCMD: another command for trying things out by hand }
  if GetEnvironmentVariable('ZMPROBE_INCMD') <> '' then
    cmd := GetEnvironmentVariable('ZMPROBE_INCMD');
  if not Run(APipe, cmd, sent, 9, got) then Exit(2);
  back := FromOd(got);
  WriteLn(Format('  od printed %d bytes back', [Length(back)]));
  if Compare(sent, back) and (back = sent) then Result := 0 else Result := 1;
  if Result <> 0 then
  begin
    WriteLn('  what the program printed (first 512 bytes):');
    DumpHex(Copy(got, 1, 512));
  end;
end;

function DoSz: Integer;
const
  ZrqInit: RawByteString = '**'#$18'B00000000000000'#13#$8A#$11;
var
  dir, name, wsl: string;
  f: TFileStream;
  data, got: RawByteString;
  i: Integer;
begin
  dir := IncludeTrailingPathDelimiter(GetTempDir(False));
  name := dir + 'zmprobe-4k.bin';
  SetLength(data, 4096);
  for i := 0 to 4095 do data[i + 1] := AnsiChar(i and 255);
  f := TFileStream.Create(name, fmCreate);
  try
    f.WriteBuffer(data[1], Length(data));
  finally
    f.Free;
  end;
  { C:\Users\x\... -> /mnt/c/Users/x/... }
  wsl := '/mnt/' + LowerCase(name[1]) + StringReplace(Copy(name, 3, MaxInt), '\', '/', [rfReplaceAll]);
  if not Run(False, 'wsl.exe -d Ubuntu -- sz ''' + wsl + '''', '', 3, got) then Exit(2);
  WriteLn(Format('  received %d bytes:', [Length(got)]));
  DumpHex(Copy(got, 1, 512));
  if Pos(ZrqInit, got) > 0 then
  begin
    WriteLn('  the ZRQINIT hex header arrived whole');
    Result := 0;
  end
  else
  begin
    WriteLn('  the ZRQINIT hex header did NOT arrive whole');
    Result := 1;
  end;
  DeleteFile(name);
end;

var
  mode: string;
  code: Integer;
begin
  mode := ParamStr(1);
  WriteLn('zmprobe ', mode);
  if mode = '--conpty-out' then code := DoOut(False)
  else if mode = '--pipe-out' then code := DoOut(True)
  else if mode = '--conpty-in' then code := DoIn(False, False)
  else if mode = '--conpty-in-printable' then code := DoIn(False, True)
  else if mode = '--pipe-in' then code := DoIn(True, False)
  else if mode = '--conpty-sz' then code := DoSz
  else
  begin
    WriteLn('zmprobe --conpty-out | --conpty-in | --conpty-sz | --pipe-out | --pipe-in');
    code := 2;
  end;
  if code = 0 then WriteLn('RESULT: as sent')
  else if code = 1 then WriteLn('RESULT: NOT as sent')
  else WriteLn('RESULT: could not run');
  Halt(code);
end.
