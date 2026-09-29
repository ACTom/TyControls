unit uptyunix;

{ The Linux / macOS PTY for the terminal example: posix_openpt, a forked child on the
  slave side as a session leader with the terminal as its controlling tty, and poll
  with a wake-up pipe so that closing never waits on a blocked read or write.

  posix_openpt, grantpt, unlockpt and ptsname come from the C library on both systems
  (glibc, libSystem): no libutil (forkpty / openpty), which on Linux would need its
  development package to link.

  THE RULE AFTER fork: the child makes system calls only -- setsid, open, ioctl, dup2,
  close, execve, exit. An LCL program is multi-threaded; in the child only the forking
  thread exists, and a lock another thread held at the fork (the memory manager's, for
  one) stays held forever. So the program path, the argument list and the environment
  are built as PChar arrays before the fork, and the child only reads them. No strings,
  no exceptions, no WriteLn there.

  The command runs as `/bin/sh -c "<command line>"`: the shell parses the line (a list,
  a pipe, a builtin such as `exit 7` -- an `exec` in front would break all three) and,
  for a single command, most shells replace themselves with it. The environment is the example's own with TERM =
  xterm-256color and COLORTERM = truecolor (LINES and COLUMNS dropped: the size comes
  from the PTY).

  Only BaseUnix, Unix, TermIO, Classes, SysUtils: tools/terminal-ptytest runs it in WSL
  as a console program, without the LCL. }

{$mode objfpc}{$H+}

interface

{$IFDEF UNIX}
uses
  BaseUnix, Unix, TermIO, Classes, SysUtils, uptysession;

type
  TUnixPtyBackend = class(TPtyBackend)
  private
    FMaster: cint;
    FWakeRead, FWakeWrite: cint;
    FPid: TPid;
    FReaped: Boolean;
    FExitCode: Integer;
    FStrings: TStringList;           { what FArgv / FEnvp point into, kept until Shutdown }
    FArgv, FEnvp: array of PChar;
    FPath: string;
    procedure CloseFds;
    function Reap(ABlock: Boolean): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    function Start(const ACommand: string; ACols, ARows: Integer; out AError: string): Boolean; override;
    function Read(var ABuf; ACount: Integer): Integer; override;
    function Write(const ABuf; ACount: Integer): Boolean; override;
    procedure Resize(ACols, ARows: Integer); override;
    procedure Interrupt; override;
    function ExitCode(AWaitMs: Integer): Integer; override;
    procedure Shutdown; override;
    { FOR THE TESTS }
    property Pid: TPid read FPid;
  end;
{$ENDIF}

implementation

{$IFDEF UNIX}

const
  FD_CLOEXEC = 1;                    { fcntl.h; not in BaseUnix }

{ from the C library (FPC 3.2.2's RTL has none of them) }
function posix_openpt(flags: cint): cint; cdecl; external 'c' name 'posix_openpt';
function grantpt(fd: cint): cint; cdecl; external 'c' name 'grantpt';
function unlockpt(fd: cint): cint; cdecl; external 'c' name 'unlockpt';
function ptsname(fd: cint): PChar; cdecl; external 'c' name 'ptsname';

procedure SetCloExec(AFd: cint);
begin
  FpFcntl(AFd, F_SETFD, FD_CLOEXEC);
end;

procedure SetNonBlock(AFd: cint);
begin
  FpFcntl(AFd, F_SETFL, FpFcntl(AFd, F_GETFL) or O_NONBLOCK);
end;

constructor TUnixPtyBackend.Create;
begin
  inherited Create;
  FMaster := -1;
  FWakeRead := -1;
  FWakeWrite := -1;
  FPid := 0;
  FExitCode := -1;
  FStrings := TStringList.Create;
end;

destructor TUnixPtyBackend.Destroy;
begin
  Shutdown;
  FStrings.Free;
  inherited Destroy;
end;

procedure TUnixPtyBackend.CloseFds;
begin
  if FMaster >= 0 then FpClose(FMaster);
  if FWakeRead >= 0 then FpClose(FWakeRead);
  if FWakeWrite >= 0 then FpClose(FWakeWrite);
  FMaster := -1;
  FWakeRead := -1;
  FWakeWrite := -1;
end;

function TUnixPtyBackend.Start(const ACommand: string; ACols, ARows: Integer; out AError: string): Boolean;
var
  slaveName: array[0..255] of Char;
  p: PChar;
  ws: TWinSize;
  fds: TFilDes;
  i, n: Integer;
  e, name: string;
  child: TPid;
  slave: cint;
begin
  AError := '';
  Result := False;
  { the master side }
  FMaster := posix_openpt(O_RDWR or O_NOCTTY);
  if FMaster < 0 then
  begin
    AError := 'posix_openpt: ' + SysErrorMessage(fpgeterrno);
    Exit;
  end;
  if (grantpt(FMaster) <> 0) or (unlockpt(FMaster) <> 0) then
  begin
    AError := 'grantpt / unlockpt: ' + SysErrorMessage(fpgeterrno);
    CloseFds;
    Exit;
  end;
  p := ptsname(FMaster);
  if p = nil then
  begin
    AError := 'ptsname: ' + SysErrorMessage(fpgeterrno);
    CloseFds;
    Exit;
  end;
  FillChar(slaveName, SizeOf(slaveName), 0);
  StrLCopy(slaveName, p, High(slaveName));
  SetCloExec(FMaster);
  SetNonBlock(FMaster);
  FillChar(ws, SizeOf(ws), 0);
  ws.ws_row := ARows;
  ws.ws_col := ACols;
  FpIoctl(FMaster, TIOCSWINSZ, @ws);
  { the wake-up pipe: Interrupt writes, Read and Write poll it }
  if FpPipe(fds) <> 0 then
  begin
    AError := 'pipe: ' + SysErrorMessage(fpgeterrno);
    CloseFds;
    Exit;
  end;
  FWakeRead := fds[0];
  FWakeWrite := fds[1];
  SetCloExec(FWakeRead);
  SetCloExec(FWakeWrite);
  SetNonBlock(FWakeRead);
  SetNonBlock(FWakeWrite);
  { everything the child reads, built before the fork }
  FStrings.Clear;
  FPath := '/bin/sh';
  FStrings.Add(FPath);
  FStrings.Add('-c');
  FStrings.Add(ACommand);
  n := 3;
  for i := 1 to GetEnvironmentVariableCount do
  begin
    e := GetEnvironmentString(i);
    name := Copy(e, 1, Pos('=', e) - 1);
    if (name = 'TERM') or (name = 'COLORTERM') or (name = 'LINES') or (name = 'COLUMNS') or (name = '') then
      Continue;
    FStrings.Add(e);
  end;
  FStrings.Add('TERM=xterm-256color');
  FStrings.Add('COLORTERM=truecolor');
  SetLength(FArgv, n + 1);
  for i := 0 to n - 1 do
    FArgv[i] := PChar(FStrings[i]);
  FArgv[n] := nil;
  SetLength(FEnvp, FStrings.Count - n + 1);
  for i := n to FStrings.Count - 1 do
    FEnvp[i - n] := PChar(FStrings[i]);
  FEnvp[FStrings.Count - n] := nil;
  child := FpFork;
  if child < 0 then
  begin
    AError := 'fork: ' + SysErrorMessage(fpgeterrno);
    CloseFds;
    Exit;
  end;
  if child = 0 then
  begin
    { THE CHILD: system calls only (unit header) }
    FpSetsid;
    slave := FpOpen(PChar(@slaveName[0]), O_RDWR);
    if slave < 0 then FpExit(127);
    FpIoctl(slave, TIOCSCTTY, nil);
    FpDup2(slave, 0);
    FpDup2(slave, 1);
    FpDup2(slave, 2);
    if slave > 2 then FpClose(slave);
    FpExecve(PChar(FArgv[0]), PPChar(@FArgv[0]), PPChar(@FEnvp[0]));
    FpExit(127);
  end;
  FPid := child;
  FReaped := False;
  Result := True;
end;

function TUnixPtyBackend.Read(var ABuf; ACount: Integer): Integer;
var
  fds: array[0..1] of TPollFd;
  r: cint;
  n: TSsize;
  e: cint;
begin
  while True do
  begin
    fds[0].fd := FMaster;
    fds[0].events := POLLIN;
    fds[0].revents := 0;
    fds[1].fd := FWakeRead;
    fds[1].events := POLLIN;
    fds[1].revents := 0;
    r := FpPoll(@fds[0], 2, -1);
    if r < 0 then
    begin
      if fpgeterrno = ESysEINTR then Continue;
      Exit(0);
    end;
    { woken up: closing }
    if fds[1].revents <> 0 then Exit(0);
    if fds[0].revents <> 0 then
    begin
      n := FpRead(FMaster, ABuf, ACount);
      if n > 0 then Exit(n);
      if n = 0 then Exit(0);
      e := fpgeterrno;
      if (e = ESysEAGAIN) or (e = ESysEINTR) then
      begin
        { POLLHUP with nothing left to read: the slave side is gone }
        if fds[0].revents and (POLLHUP or POLLERR) <> 0 then Exit(0);
        Continue;
      end;
      Exit(0);                                   { EIO: every slave fd is closed (Linux) }
    end;
  end;
end;

function TUnixPtyBackend.Write(const ABuf; ACount: Integer): Boolean;
var
  fds: array[0..1] of TPollFd;
  p: PByte;
  left: Integer;
  n: TSsize;
  r, e: cint;
begin
  p := @ABuf;
  left := ACount;
  while left > 0 do
  begin
    fds[0].fd := FMaster;
    fds[0].events := POLLOUT;
    fds[0].revents := 0;
    fds[1].fd := FWakeRead;
    fds[1].events := POLLIN;
    fds[1].revents := 0;
    r := FpPoll(@fds[0], 2, -1);
    if r < 0 then
    begin
      if fpgeterrno = ESysEINTR then Continue;
      Exit(False);
    end;
    if fds[1].revents <> 0 then Exit(False);
    if fds[0].revents and (POLLERR or POLLHUP or POLLNVAL) <> 0 then Exit(False);
    n := FpWrite(FMaster, p^, left);
    if n < 0 then
    begin
      e := fpgeterrno;
      if (e = ESysEAGAIN) or (e = ESysEINTR) then Continue;
      Exit(False);
    end;
    Inc(p, n);
    Dec(left, n);
  end;
  Result := True;
end;

procedure TUnixPtyBackend.Resize(ACols, ARows: Integer);
var
  ws: TWinSize;
begin
  if FMaster < 0 then Exit;
  FillChar(ws, SizeOf(ws), 0);
  ws.ws_row := ARows;
  ws.ws_col := ACols;
  { the kernel sends SIGWINCH to the foreground process group }
  FpIoctl(FMaster, TIOCSWINSZ, @ws);
end;

procedure TUnixPtyBackend.Interrupt;
var
  b: Byte;
begin
  b := 1;
  if FWakeWrite >= 0 then
    FpWrite(FWakeWrite, b, 1);
  { the user closes: the whole session gets the hang-up }
  if (FPid > 0) and not FReaped then
    FpKill(-FPid, SIGHUP);
end;

function TUnixPtyBackend.Reap(ABlock: Boolean): Boolean;
var
  st: cint;
  r: TPid;
begin
  if FReaped then Exit(True);
  if FPid <= 0 then Exit(False);
  st := 0;
  if ABlock then
    r := FpWaitPid(FPid, @st, 0)
  else
    r := FpWaitPid(FPid, @st, WNOHANG);
  if r <> FPid then Exit(False);
  FReaped := True;
  if wifexited(st) then
    FExitCode := wexitstatus(st)
  else if wifsignaled(st) then
    FExitCode := 128 + wtermsig(st)
  else
    FExitCode := -1;
  Result := True;
end;

function TUnixPtyBackend.ExitCode(AWaitMs: Integer): Integer;
var
  waited: Integer;
begin
  waited := 0;
  while not Reap(False) do
  begin
    if waited >= AWaitMs then Exit(-1);
    Sleep(10);
    Inc(waited, 10);
  end;
  Result := FExitCode;
end;

procedure TUnixPtyBackend.Shutdown;
begin
  if (FPid > 0) and not FReaped then
  begin
    FpKill(-FPid, SIGHUP);
    FpKill(FPid, SIGHUP);
    if ExitCode(1000) = -1 then
      if not FReaped then
      begin
        FpKill(-FPid, SIGKILL);
        FpKill(FPid, SIGKILL);
        Reap(True);
      end;
  end;
  CloseFds;
end;

{$ENDIF}

end.
