unit uwslpipe;

{ The pipe mode's WSL entries (7 期验收反馈).

  A pipe has no line discipline, so the WSL entry opens a terminal in Linux: the login
  shell runs on a PTY there. What opens it depends on what the distribution has, and
  wsl.exe -e runs one program with no shell around it (a missing one is only
  "execvpe(script) failed"). So the entry is a short POSIX sh script (dash and busybox
  run it) that tries, in turn:

    1. script (util-linux / bsdutils): script runs its -c command with $SHELL, so the
       entry hands it /bin/sh for that (whatever the login shell's syntax: fish too) and
       keeps the login shell in TYTERM_SHELL; the command gives the PTY the grid (stty,
       %COLS% / %ROWS%), writes the shell's PID and PTY into %TTYFILE% and execs the login
       shell with its own $SHELL back;
    2. python3: a PTY helper (WslPtyHelperSource, base64 in the command: no quotes to
       nest) -- pty.fork, the child sets the grid on its PTY (TIOCSWINSZ), writes the
       same "PID PTY" line into %TTYFILE% and execs the login shell; the parent moves the
       bytes between the pipe and the PTY as they are and ends with the shell's exit code;
    3. neither: one fixed line (WslNoPtyHelperMarker) and exit 127. The example then says
       what to install (IsWslNoPtyHelperExit).

  The login shell is $SHELL, /bin/sh when it is empty. Either way the side process that
  sets a later size (uwslresize) finds the same file with the same line in it.

  One entry per distribution (wsl.exe --list --quiet, docker-desktop's left out), the
  default first (the "*" of wsl.exe --list --verbose); each with -d (a name with a space in
  double quotes: wsl.exe --import takes one), which the side process takes over. wsl.exe
  writes these lists in UTF-16LE (with WSL_UTF8=1 in UTF-8): the parse takes both. The
  lists are asked once, the first time "Pipe" is ticked (about a quarter of a second, the
  two at once), and kept. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, base64;

const
  { the entry without -d: the default distribution. %COLS% / %ROWS% (umain), %TTYFILE%
    and %PTYHELPER% (the backend, uwslresize) are filled in at the start }
  PipeWslCommand = 'wsl.exe -e sh -c "'
    + 'if command -v script >/dev/null 2>&1; then '
    + 'TYTERM_SHELL=${SHELL:-/bin/sh}; SHELL=/bin/sh; export TYTERM_SHELL SHELL; exec script -qfc '
    + '''stty cols %COLS% rows %ROWS%; echo $$ $(tty) > %TTYFILE%; '
    + 'SHELL=$TYTERM_SHELL; unset TYTERM_SHELL; exec $SHELL -il'' /dev/null; fi; '
    + 'if command -v python3 >/dev/null 2>&1; then exec python3 -c '
    + '''import sys,base64;exec(base64.b64decode(sys.argv[1]))'' %PTYHELPER% %COLS% %ROWS% %TTYFILE%; fi; '
    + 'echo ''tyterm: neither script nor python3 in this WSL distribution''; exit 127"';
  { in the command: the PTY helper, base64 }
  WslPtyHelperPlaceholder = '%PTYHELPER%';
  { what the entry writes and how it ends when the distribution has neither }
  WslNoPtyHelperMarker = 'tyterm: neither script nor python3 in this WSL distribution';
  WslNoPtyHelperExitCode = 127;

  { The python3 PTY helper. argv: -c, this in base64, columns, rows, the file. The child
    sets its PTY's size itself, before the exec (no race with the shell's first look at
    it). The parent: the pipe's bytes into the PTY (buffered, the PTY is non-blocking --
    a paste larger than the PTY takes does not stall the other way), the PTY's out to the
    pipe; it ends when the PTY is closed on the far side, the shell has exited (what is
    left is read first) or the pipe's input ends (the shell then gets SIGHUP). }
  WslPtyHelperSource =
    'import os,sys,pty,select,fcntl,termios,struct'#10 +
    'c,r,f=int(sys.argv[2]),int(sys.argv[3]),sys.argv[4]'#10 +
    'sh=os.environ.get(''SHELL'') or ''/bin/sh'''#10 +
    'pid,m=pty.fork()'#10 +
    'if pid==0:'#10 +
    '  try:'#10 +
    '    fcntl.ioctl(0,termios.TIOCSWINSZ,struct.pack(''HHHH'',r,c,0,0))'#10 +
    '    with open(f,''w'') as o:o.write(''%d %s\n''%(os.getpid(),os.ttyname(0)))'#10 +
    '  except Exception:pass'#10 +
    '  for x in(sh,''/bin/sh''):'#10 +
    '    try:os.execvp(x,[x,''-il''])'#10 +
    '    except Exception:pass'#10 +
    '  os._exit(127)'#10 +
    'fcntl.fcntl(m,fcntl.F_SETFL,fcntl.fcntl(m,fcntl.F_GETFL)|os.O_NONBLOCK)'#10 +
    'b=b'''';eof=False;st=None'#10 +
    'def out(d):'#10 +
    '  while d:d=d[os.write(1,d):]'#10 +
    'while st is None:'#10 +
    '  rl=[m]'#10 +
    '  if not eof and len(b)<65536:rl.append(0)'#10 +
    '  try:rr,ww,_=select.select(rl,[m] if b else [],[],0.5)'#10 +
    '  except InterruptedError:continue'#10 +
    '  if m in rr:'#10 +
    '    try:d=os.read(m,65536)'#10 +
    '    except BlockingIOError:d=None'#10 +
    '    except OSError:d=b'''''#10 +
    '    if d==b'''':break'#10 +
    '    if d:out(d)'#10 +
    '  if 0 in rr:'#10 +
    '    d=os.read(0,65536)'#10 +
    '    if d:b+=d'#10 +
    '    else:eof=True'#10 +
    '  if b and m in ww:'#10 +
    '    try:b=b[os.write(m,b):]'#10 +
    '    except BlockingIOError:pass'#10 +
    '    except OSError:b=b'''''#10 +
    '  if eof and not b:break'#10 +
    '  p,s=os.waitpid(pid,os.WNOHANG)'#10 +
    '  if p:'#10 +
    '    st=s'#10 +
    '    while True:'#10 +
    '      try:d=os.read(m,65536)'#10 +
    '      except OSError:break'#10 +
    '      if not d:break'#10 +
    '      out(d)'#10 +
    'os.close(m)'#10 +
    'if st is None:_,st=os.waitpid(pid,0)'#10 +
    'sys.exit(os.WEXITSTATUS(st) if os.WIFEXITED(st) else 128+os.WTERMSIG(st))'#10;

{ the entry for one distribution ('' = the default: PipeWslCommand as it is); a name
  with anything but letters, digits, '.', '_', '-' in double quotes }
function WslPipeCommandFor(const ADistro: string): string;
{ %PTYHELPER% -> the helper in base64 (every one; a command without it comes back as it is) }
function ExpandWslPtyHelper(const ACommand: string): string;
{ what wsl.exe wrote: UTF-16LE (a BOM or not) or UTF-8 -> UTF-8, NULs gone }
function DecodeWslOutput(const ARaw: RawByteString): string;
{ wsl.exe --list --quiet -> the names, in its order: blank lines, a name with a control
  character or a double quote and docker-desktop* left out, each once }
function ParseWslDistros(const AQuietRaw: RawByteString): TStringArray;
{ wsl.exe --list --verbose -> the default distribution's name (the row with "*", matched
  against ANames: a name may have a space; '' = none) }
function ParseWslDefaultDistro(const AVerboseRaw: RawByteString; const ANames: TStringArray): string;
{ the default first (when it is among them), the rest in their order }
function OrderWslDistros(const ANames: TStringArray; const ADefault: string): TStringArray;
{ both lists -> the names the pipe mode lists; the verbose one may have failed ('') }
function WslPipeDistrosFrom(const AQuietRaw, AVerboseRaw: RawByteString): TStringArray;
{ the entry ended because the distribution has neither script nor python3 }
function IsWslNoPtyHelperExit(ACode: Int64; const AOutput: RawByteString): Boolean;

type
  { runs wsl.exe --list --quiet and --list --verbose; an Ok is False when that one did
    not start, did not end in time or did not end with 0 }
  TWslListRunner = procedure(out AQuiet, AVerbose: RawByteString; out AQuietOk, AVerboseOk: Boolean);

var
  { the example's runner (Windows: the real wsl.exe); the tests put canned output here
    (and call ForgetWslPipeDistros) }
  WslListRunner: TWslListRunner = nil;

{ the distributions the pipe mode lists: asked once (WslListRunner), then kept. Empty:
  the lists could not be had -- the caller lists the entry without -d }
function WslPipeDistros: TStringArray;
procedure ForgetWslPipeDistros;

implementation

{$IFDEF MSWINDOWS}
uses
  process;
{$ENDIF}

{ quoted for the command line when it has anything but letters, digits, '.', '_', '-' }
function QuoteDistro(const S: string): string;
var
  i: Integer;
begin
  Result := S;
  for i := 1 to Length(S) do
    if not (S[i] in ['A'..'Z', 'a'..'z', '0'..'9', '.', '_', '-']) then
      Exit('"' + S + '"');
end;

function WslPipeCommandFor(const ADistro: string): string;
const
  Head = 'wsl.exe';
begin
  if ADistro = '' then
    Exit(PipeWslCommand);
  Result := Head + ' -d ' + QuoteDistro(ADistro) + Copy(PipeWslCommand, Length(Head) + 1, MaxInt);
end;

function ExpandWslPtyHelper(const ACommand: string): string;
begin
  if Pos(WslPtyHelperPlaceholder, ACommand) = 0 then
    Exit(ACommand);
  Result := StringReplace(ACommand, WslPtyHelperPlaceholder, EncodeStringBase64(WslPtyHelperSource),
    [rfReplaceAll]);
end;

function DecodeWslOutput(const ARaw: RawByteString): string;
var
  u: UnicodeString;
  i, n, start: Integer;
  utf16: Boolean;
begin
  start := 1;
  utf16 := False;
  if (Length(ARaw) >= 2) and (ARaw[1] = #$FF) and (ARaw[2] = #$FE) then
  begin
    utf16 := True;
    start := 3;
  end
  else if (Length(ARaw) >= 2) and (ARaw[2] = #0) then
    utf16 := True;                       { ASCII in UTF-16LE: every second byte 0 }
  if utf16 then
  begin
    n := (Length(ARaw) - start + 1) div 2;
    SetLength(u, n);
    for i := 0 to n - 1 do
      u[i + 1] := WideChar(Ord(ARaw[start + 2 * i]) or (Ord(ARaw[start + 2 * i + 1]) shl 8));
    Result := UTF8Encode(u);
  end
  else
  begin
    Result := ARaw;
    if (Length(Result) >= 3) and (Result[1] = #$EF) and (Result[2] = #$BB) and (Result[3] = #$BF) then
      Delete(Result, 1, 3);
  end;
  Result := StringReplace(Result, #0, '', [rfReplaceAll]);
end;

{ a name the entry can carry: not empty, no control character, no double quote (a
  command line could not quote it for wsl.exe and the side process alike). A space is
  possible: wsl.exe --import "My Distro" makes one }
function IsListableName(const S: string): Boolean;
var
  i: Integer;
begin
  Result := S <> '';
  for i := 1 to Length(S) do
    if (S[i] < ' ') or (S[i] = '"') or (S[i] = #127) then
      Exit(False);
end;

function SplitLines(const S: string): TStringArray;
var
  sl: TStringList;
  i: Integer;
begin
  Result := nil;
  sl := TStringList.Create;
  try
    sl.Text := StringReplace(S, #13, '', [rfReplaceAll]);
    SetLength(Result, sl.Count);
    for i := 0 to sl.Count - 1 do
      Result[i] := sl[i];
  finally
    sl.Free;
  end;
end;

function ParseWslDistros(const AQuietRaw: RawByteString): TStringArray;
var
  lines: TStringArray;
  i, j: Integer;
  s: string;
  seen: Boolean;
begin
  Result := nil;
  lines := SplitLines(DecodeWslOutput(AQuietRaw));
  for i := 0 to High(lines) do
  begin
    s := Trim(lines[i]);
    if not IsListableName(s) then Continue;
    if Pos('docker-desktop', LowerCase(s)) = 1 then Continue;
    seen := False;
    for j := 0 to High(Result) do
      if SameText(Result[j], s) then seen := True;
    if seen then Continue;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := s;
  end;
end;

function ParseWslDefaultDistro(const AVerboseRaw: RawByteString; const ANames: TStringArray): string;
var
  lines: TStringArray;
  i, j, p: Integer;
  s: string;
begin
  Result := '';
  lines := SplitLines(DecodeWslOutput(AVerboseRaw));
  for i := 0 to High(lines) do
  begin
    s := TrimLeft(lines[i]);
    if (s = '') or (s[1] <> '*') then Continue;
    s := TrimLeft(Copy(s, 2, MaxInt));
    { the row goes on with the state and the version (in the system's language): the
      longest known name the row starts with, followed by a blank }
    for j := 0 to High(ANames) do
      if (Length(ANames[j]) > Length(Result)) and (Copy(s, 1, Length(ANames[j])) = ANames[j])
        and ((Length(s) = Length(ANames[j])) or (s[Length(ANames[j]) + 1] in [' ', #9])) then
        Result := ANames[j];
    if Result <> '' then Exit;
    { no names to match: the first word }
    p := 1;
    while (p <= Length(s)) and not (s[p] in [' ', #9]) do Inc(p);
    Exit(Copy(s, 1, p - 1));
  end;
end;

function OrderWslDistros(const ANames: TStringArray; const ADefault: string): TStringArray;
var
  i, n, d: Integer;
begin
  d := -1;
  if ADefault <> '' then
    for i := High(ANames) downto 0 do
      if SameText(ANames[i], ADefault) then d := i;
  Result := nil;
  SetLength(Result, Length(ANames));
  n := 0;
  if d >= 0 then
  begin
    Result[0] := ANames[d];
    n := 1;
  end;
  for i := 0 to High(ANames) do
    if i <> d then
    begin
      Result[n] := ANames[i];
      Inc(n);
    end;
end;

function WslPipeDistrosFrom(const AQuietRaw, AVerboseRaw: RawByteString): TStringArray;
var
  names: TStringArray;
begin
  names := ParseWslDistros(AQuietRaw);
  Result := OrderWslDistros(names, ParseWslDefaultDistro(AVerboseRaw, names));
end;

function IsWslNoPtyHelperExit(ACode: Int64; const AOutput: RawByteString): Boolean;
begin
  Result := (ACode = WslNoPtyHelperExitCode) and (Pos(WslNoPtyHelperMarker, AOutput) > 0);
end;

{ ---- asking wsl.exe ------------------------------------------------------------------- }

{$IFDEF MSWINDOWS}
const
  { wsl.exe --list takes about a quarter of a second; a WSL that does not answer in this
    long gets the entry without -d }
  WslListWaitMs = 5000;

{ both lists at once, no window; a process still running after WslListWaitMs is ended
  by its handle }
procedure RunWslLists(out AQuiet, AVerbose: RawByteString; out AQuietOk, AVerboseOk: Boolean);
var
  p: array[0..1] of TProcess;
  outs: array[0..1] of RawByteString;
  oks: array[0..1] of Boolean;
  buf: array[0..4095] of Byte;
  i, n: Integer;
  t0: QWord;
  busy, any: Boolean;
begin
  for i := 0 to 1 do
  begin
    outs[i] := '';
    oks[i] := False;
    p[i] := TProcess.Create(nil);
  end;
  try
    for i := 0 to 1 do
    begin
      p[i].Executable := 'wsl.exe';
      p[i].Parameters.Add('--list');
      if i = 0 then
        p[i].Parameters.Add('--quiet')
      else
        p[i].Parameters.Add('--verbose');
      p[i].Options := [poUsePipes, poStderrToOutPut, poNoConsole];
      p[i].ShowWindow := swoHide;
      try
        p[i].Execute;
      except
        FreeAndNil(p[i]);
      end;
    end;
    t0 := GetTickCount64;
    repeat
      busy := False;
      any := False;
      for i := 0 to 1 do
        if p[i] <> nil then
        begin
          n := p[i].Output.NumBytesAvailable;
          if n > 0 then
          begin
            if n > SizeOf(buf) then n := SizeOf(buf);
            n := p[i].Output.Read(buf, n);
            if n > 0 then
            begin
              SetLength(outs[i], Length(outs[i]) + n);
              Move(buf, outs[i][Length(outs[i]) - n + 1], n);
              any := True;
            end;
          end;
          if p[i].Running or (p[i].Output.NumBytesAvailable > 0) then
            busy := True;
        end;
      if not busy then Break;
      if not any then Sleep(10);
    until GetTickCount64 - t0 > WslListWaitMs;
    for i := 0 to 1 do
      if p[i] <> nil then
        if p[i].Running then
          p[i].Terminate(1)
        else
          oks[i] := p[i].ExitStatus = 0;
  finally
    for i := 0 to 1 do
      p[i].Free;
  end;
  AQuiet := outs[0];
  AVerbose := outs[1];
  AQuietOk := oks[0];
  AVerboseOk := oks[1];
end;
{$ENDIF}

var
  GDistros: TStringArray;
  GAsked: Boolean = False;

function WslPipeDistros: TStringArray;
var
  q, v: RawByteString;
  qok, vok: Boolean;
begin
  if not GAsked then
  begin
    GAsked := True;
    GDistros := nil;
    if Assigned(WslListRunner) then
    begin
      WslListRunner(q, v, qok, vok);
      if not vok then v := '';
      if qok then
        GDistros := WslPipeDistrosFrom(q, v);
    end;
  end;
  Result := Copy(GDistros);
end;

procedure ForgetWslPipeDistros;
begin
  GAsked := False;
  GDistros := nil;
end;

initialization
  {$IFDEF MSWINDOWS}
  WslListRunner := @RunWslLists;
  {$ENDIF}
end.
