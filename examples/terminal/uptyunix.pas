unit uptyunix;

{ The Linux / macOS PTY for the terminal example: posix_openpt, a forked child on the
  slave side as a session leader with the terminal as its controlling tty, and poll
  with a wake-up pipe so that closing never waits on a blocked read or write.

  posix_openpt, grantpt, unlockpt and ptsname come from the C library on both systems
  (glibc, libSystem): no libutil (forkpty / openpty), which on Linux would need its
  development package to link.

  THE RULE AFTER fork: the child makes system calls only -- sigprocmask, sigaction,
  close, setsid, open, ioctl, dup2, execve, exit (all async-signal-safe). An LCL program
  is multi-threaded; in the child only the forking thread exists, and a lock another
  thread held at the fork (the memory manager's, for one) stays held forever. So the
  program path, the argument list, the environment, the empty signal set and the fd
  limit are all made before the fork, and the child only reads them. No strings, no
  exceptions, no WriteLn there.

  What the child must not inherit from the host: the forking thread's signal mask (it
  is reset to empty), ignored signals (an ignored signal stays ignored across execve --
  a host that ignores SIGPIPE would hand `yes | head -1` a `yes` that never dies; 1..31
  go back to SIG_DFL), and the host's descriptors that were opened without close-on-exec
  (every fd from 3 to the soft RLIMIT_NOFILE, at most 65536, is closed).

  The command runs as `/bin/sh -c "<command line>"`: the shell parses the line (a list,
  a pipe, a builtin such as `exit 7` -- an `exec` in front would break all three) and,
  for a single command, most shells replace themselves with it. The environment is the
  example's own with TERM = xterm-256color and COLORTERM = truecolor (LINES and COLUMNS
  dropped: the size comes from the PTY).

  Waiting: poll on the master and the wake-up pipe. macOS's poll() does not support
  character devices and may answer POLLNVAL for the master; the first such answer
  switches this backend to select() for good (ForceSelect makes the tests take that
  path on Linux).

  Closing (the session's finisher does the waiting, never the main thread): BeginClose
  sends the whole session SIGHUP; FinishClose waits for the child to be reaped, then
  SIGKILLs it; Interrupt writes the wake-up pipe.

  Only BaseUnix, Unix, TermIO, Classes, SysUtils, SyncObjs: tools/terminal-ptytest runs it
  in WSL as a console program, without the LCL. }

{$mode objfpc}{$H+}

interface

{$IFDEF UNIX}
uses
  BaseUnix, Unix, TermIO, Classes, SysUtils, SyncObjs, uptysession;

type
  TUnixPtyBackend = class(TPtyBackend)
  private
    FMaster: cint;
    FWakeRead, FWakeWrite: cint;
    FPid: TPid;
    FReaped: Boolean;
    FExitCode: Int64;
    FReapLock: TCriticalSection;       { the reader (ExitCode) and the finisher both reap }
    FStrings: TStringList;           { what FArgv / FEnvp point into, kept until Shutdown }
    FArgv, FEnvp: array of PChar;
    FPath: string;
    FUseSelect: Boolean;
    FKilled: Boolean;
    procedure CloseFds;
    function Reap(ABlock: Boolean): Boolean;
    { 1 = the master is ready (ARevents: POLLIN / POLLOUT / POLLHUP ...), 0 = woken
      (closing), -1 = an error }
    function WaitMaster(AForWrite: Boolean; out ARevents: cint): Integer;
  public
    { FOR THE TESTS: select() from the start, as on macOS after a POLLNVAL }
    ForceSelect: Boolean;
    constructor Create;
    destructor Destroy; override;
    function Start(const ACommand: string; ACols, ARows: Integer; out AError: string): Boolean; override;
    function Read(var ABuf; ACount: Integer): Integer; override;
    function Write(const ABuf; ACount: Integer): Boolean; override;
    procedure Resize(ACols, ARows: Integer); override;
    procedure BeginClose; override;
    function FinishClose(AWaitMs: Integer): TPtyCloseResult; override;
    procedure Interrupt; override;
    function ExitCode(AWaitMs: Integer): Int64; override;
    procedure Shutdown; override;
    { FOR THE TESTS }
    property Pid: TPid read FPid;
    property UsesSelect: Boolean read FUseSelect;
    property Killed: Boolean read FKilled;
  end;
{$ENDIF}

implementation

{$IFDEF UNIX}

const
  FD_CLOEXEC = 1;                    { fcntl.h; not in BaseUnix }
  { the child closes the fds from 3 up to the soft limit, but no further }
  MaxFdToClose = 65536;

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
  FReapLock := TCriticalSection.Create;
end;

destructor TUnixPtyBackend.Destroy;
begin
  Shutdown;
  FStrings.Free;
  FReapLock.Free;
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
  slave, fd, fdLimit, sig: cint;
  emptySet: TSigSet;
  dfl: SigActionRec;
  rl: TRLimit;
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
  FUseSelect := ForceSelect;
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
  FpSigEmptySet(emptySet);
  FillChar(dfl, SizeOf(dfl), 0);
  dfl.sa_handler := SigActionHandler(SIG_DFL);
  fdLimit := 1024;
  if (FpGetRLimit(RLIMIT_NOFILE, @rl) = 0) and (rl.rlim_cur > 3) then
  begin
    if rl.rlim_cur > MaxFdToClose then fdLimit := MaxFdToClose else fdLimit := rl.rlim_cur;
  end;
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
    FpSigProcMask(SIG_SETMASK, @emptySet, nil);
    for sig := 1 to 31 do
      FpSigAction(sig, @dfl, nil);             { SIGKILL / SIGSTOP answer EINVAL: fine }
    for fd := 3 to fdLimit - 1 do
      FpClose(fd);                             { the master and the wake pipe too }
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

function TUnixPtyBackend.WaitMaster(AForWrite: Boolean; out ARevents: cint): Integer;
var
  fds: array[0..1] of TPollFd;
  rs, ws: TFDSet;
  r, top: cint;
begin
  ARevents := 0;
  while True do
  begin
    if not FUseSelect then
    begin
      fds[0].fd := FMaster;
      if AForWrite then fds[0].events := POLLOUT else fds[0].events := POLLIN;
      fds[0].revents := 0;
      fds[1].fd := FWakeRead;
      fds[1].events := POLLIN;
      fds[1].revents := 0;
      r := FpPoll(@fds[0], 2, -1);
      if r < 0 then
      begin
        if fpgeterrno = ESysEINTR then Continue;
        Exit(-1);
      end;
      { woken up: closing }
      if fds[1].revents <> 0 then Exit(0);
      if fds[0].revents and POLLNVAL <> 0 then
      begin
        { macOS: poll() and a character device (unit header). The fd itself is fine --
          it is closed only after both threads are gone; select says so if it is not }
        FUseSelect := True;
        Continue;
      end;
      if fds[0].revents <> 0 then
      begin
        ARevents := fds[0].revents;
        Exit(1);
      end;
    end
    else
    begin
      fpFD_ZERO(rs);
      fpFD_ZERO(ws);
      fpFD_SET(FWakeRead, rs);
      if AForWrite then fpFD_SET(FMaster, ws) else fpFD_SET(FMaster, rs);
      top := FMaster;
      if FWakeRead > top then top := FWakeRead;
      r := FpSelect(top + 1, @rs, @ws, nil, nil);
      if r < 0 then
      begin
        if fpgeterrno = ESysEINTR then Continue;
        Exit(-1);
      end;
      if fpFD_ISSET(FWakeRead, rs) = 1 then Exit(0);
      if AForWrite and (fpFD_ISSET(FMaster, ws) = 1) then
      begin
        ARevents := POLLOUT;
        Exit(1);
      end;
      if not AForWrite and (fpFD_ISSET(FMaster, rs) = 1) then
      begin
        { select does not tell a hang-up from data: the read that follows does }
        ARevents := POLLIN;
        Exit(1);
      end;
    end;
  end;
end;

function TUnixPtyBackend.Read(var ABuf; ACount: Integer): Integer;
var
  rev: cint;
  n: TSsize;
  e: cint;
begin
  while True do
  begin
    if WaitMaster(False, rev) <> 1 then Exit(0);
    n := FpRead(FMaster, ABuf, ACount);
    if n > 0 then Exit(n);
    if n = 0 then Exit(0);
    e := fpgeterrno;
    if (e = ESysEAGAIN) or (e = ESysEINTR) then
    begin
      { POLLHUP with nothing left to read: the slave side is gone }
      if rev and (POLLHUP or POLLERR) <> 0 then Exit(0);
      Continue;
    end;
    Exit(0);                                   { EIO: every slave fd is closed (Linux) }
  end;
end;

function TUnixPtyBackend.Write(const ABuf; ACount: Integer): Boolean;
var
  p: PByte;
  left: Integer;
  n: TSsize;
  rev, e: cint;
begin
  p := @ABuf;
  left := ACount;
  while left > 0 do
  begin
    if WaitMaster(True, rev) <> 1 then Exit(False);
    if rev and (POLLERR or POLLHUP or POLLNVAL) <> 0 then Exit(False);
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

{ the main thread: the whole session gets the hang-up; nothing waits here }
procedure TUnixPtyBackend.BeginClose;
begin
  FReapLock.Enter;
  try
    if (FPid > 0) and not FReaped then
      FpKill(-FPid, SIGHUP);
  finally
    FReapLock.Leave;
  end;
end;

function TUnixPtyBackend.FinishClose(AWaitMs: Integer): TPtyCloseResult;
begin
  Result := pcrGone;
  if FPid <= 0 then Exit;
  if ExitCode(AWaitMs) <> -1 then Exit;
  FReapLock.Enter;
  try
    if FReaped then Exit;
    { it ignores the hang-up: the session, then the child itself }
    FKilled := True;
    Result := pcrKilled;
    FpKill(-FPid, SIGKILL);
    FpKill(FPid, SIGKILL);
  finally
    FReapLock.Leave;
  end;
  if ExitCode(PtyKillWaitMs) = -1 then
    Result := pcrStuck;                        { not even SIGKILL (uninterruptible) }
end;

procedure TUnixPtyBackend.Interrupt;
var
  b: Byte;
begin
  b := 1;
  if FWakeWrite >= 0 then
    FpWrite(FWakeWrite, b, 1);
end;

function TUnixPtyBackend.Reap(ABlock: Boolean): Boolean;
var
  st: cint;
  r: TPid;
begin
  FReapLock.Enter;
  try
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
  finally
    FReapLock.Leave;
  end;
end;

function TUnixPtyBackend.ExitCode(AWaitMs: Integer): Int64;
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
  { after FinishClose the child is reaped; a backend freed without it (never through a
    session's finisher) takes the child down here, bounded }
  if (FPid > 0) and not Reap(False) then
  begin
    FpKill(-FPid, SIGHUP);
    FpKill(FPid, SIGHUP);
    if ExitCode(1000) = -1 then
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
