program ptytest;

{ The terminal example's Unix PTY backend (examples/terminal/uptyunix + uptysession),
  run as a plain FPC console program: no LCL, no package. Built and run in WSL:

    cd tools/terminal-ptytest && mkdir -p lib && \
      fpc -Mobjfpc -Sh -FUlib -Fu../../examples/terminal -optytest ptytest.lpr && ./ptytest

  Each case starts a command through the session, pumps its output on the main thread
  (woken by the session's OnWake, as the example is by QueueAsyncCall), counts it back
  with Delivered, and waits at most 10 s. Closing returns at once; the cases that close
  wait for the session's finisher (PtyWaitForFinishers) before they look for the child.
  Prints PASS / FAIL per case and, last, "ptytest: N passed, M failed"; the exit code
  is M. }

{$mode objfpc}{$H+}

uses
  cthreads, Classes, SysUtils, SyncObjs, BaseUnix, uptysession, uptyunix;

type
  TWaker = class
  public
    Event: TEvent;
    constructor Create;
    destructor Destroy; override;
    procedure Wake(Sender: TObject);
  end;

  TRun = record
    Output: RawByteString;
    Code: Int64;
    Ended: Boolean;
    MaxOutstanding: Int64;
    Error: string;
  end;

var
  Passed, Failed: Integer;

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

procedure Pass(const AName: string);
begin
  Inc(Passed);
  WriteLn('PASS ', AName);
end;

procedure Fail(const AName, AWhy: string);
begin
  Inc(Failed);
  WriteLn('FAIL ', AName, ': ', AWhy);
end;

{ ADelayMs: sleep after each pump before counting it back (back-pressure);
  AResize: resize to 100 x 30 right after the start }
function Run(const ACommand: string; AHigh, ADelayMs: Integer; AResize: Boolean;
  ATimeoutMs: Integer = 10000; ASelect: Boolean = False): TRun;
var
  waker: TWaker;
  s: TPtySession;
  b: TUnixPtyBackend;
  data: RawByteString;
  exited: Boolean;
  code: Int64;
  t0: QWord;
begin
  Result := Default(TRun);
  Result.Code := -2;
  waker := TWaker.Create;
  b := TUnixPtyBackend.Create;
  b.ForceSelect := ASelect;
  s := TPtySession.Create(b, AHigh, AHigh div 4, 65536);
  try
    s.OnWake := @waker.Wake;
    if not s.Start(ACommand, 80, 24, Result.Error) then
      Exit;
    if AResize then
      s.Resize(100, 30);
    t0 := GetTickCount64;
    while GetTickCount64 - t0 < QWord(ATimeoutMs) do
    begin
      waker.Event.WaitFor(100);
      if s.Pump(data, exited, code) then
      begin
        Result.Output := Result.Output + data;
        if ADelayMs > 0 then Sleep(ADelayMs);
        s.Delivered(Length(data));
        if exited then
        begin
          Result.Ended := True;
          Result.Code := code;
          Break;
        end;
      end;
    end;
    Result.MaxOutstanding := s.MaxOutstanding;
  finally
    s.Free;
    { the waker goes after the finisher: no wake after Close, but be plain about it }
    PtyWaitForFinishers(PtyExitWaitMs);
    waker.Free;
  end;
end;

function CountOf(AChar: Char; const S: RawByteString): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 1 to Length(S) do
    if S[i] = AChar then Inc(Result);
end;

procedure T1;
var
  r: TRun;
begin
  r := Run('echo tyterm-ok', 1048576, 0, False);
  if not r.Ended then Fail('T1 output', 'no end: ' + r.Error)
  else if Pos('tyterm-ok', r.Output) = 0 then Fail('T1 output', 'got ' + r.Output)
  else if r.Code <> 0 then Fail('T1 output', 'code ' + IntToStr(r.Code))
  else Pass('T1 output');
end;

procedure T2;
var
  r: TRun;
begin
  r := Run('exit 7', 1048576, 0, False);
  if not r.Ended then Fail('T2 exit code', 'no end: ' + r.Error)
  else if r.Code <> 7 then Fail('T2 exit code', 'code ' + IntToStr(r.Code))
  else Pass('T2 exit code');
end;

procedure T3;
var
  r: TRun;
begin
  r := Run('stty size', 1048576, 0, False);
  if Pos('24 80', r.Output) = 0 then Fail('T3 initial size', 'got ' + r.Output)
  else Pass('T3 initial size');
end;

procedure T4;
var
  r: TRun;
begin
  r := Run('sleep 0.5; stty size', 1048576, 0, True);
  if Pos('30 100', r.Output) = 0 then Fail('T4 resize', 'got ' + r.Output)
  else Pass('T4 resize');
end;

procedure T5;
const
  N = 2000000;
var
  r: TRun;
begin
  r := Run('head -c 2000000 /dev/zero | tr ''\0'' x', 256 * 1024, 20, False, 60000);
  if not r.Ended then Fail('T5 big output', 'no end')
  else if CountOf('x', r.Output) <> N then
    Fail('T5 big output', Format('%d x of %d', [CountOf('x', r.Output), N]))
  else if r.MaxOutstanding > 256 * 1024 + 65536 then
    Fail('T5 big output', Format('%d outstanding', [r.MaxOutstanding]))
  else Pass(Format('T5 big output (max %d outstanding)', [r.MaxOutstanding]));
end;

procedure T6;
var
  s: TPtySession;
  b: TUnixPtyBackend;
  err: string;
  pid: TPid;
  t0, took: QWord;
begin
  b := TUnixPtyBackend.Create;
  s := TPtySession.Create(b);
  try
    if not s.Start('sleep 100', 80, 24, err) then
    begin
      Fail('T6 close', err);
      Exit;
    end;
    pid := b.Pid;
    Sleep(300);
    t0 := GetTickCount64;
    s.Close;
    took := GetTickCount64 - t0;
    if took > 200 then Fail('T6 close', Format('Close took %d ms', [took]))
    else if not PtyWaitForFinishers(PtyExitWaitMs) then Fail('T6 close', 'the finisher did not finish')
    else if (FpKill(pid, 0) = 0) or (fpgeterrno <> ESysESRCH) then Fail('T6 close', 'the child is still there')
    else Pass(Format('T6 close (%d ms, gone after %d ms)', [took, GetTickCount64 - t0]));
  finally
    s.Free;
  end;
end;

procedure T7;
var
  r: TRun;
begin
  r := Run('echo $TERM', 1048576, 0, False);
  if Pos('xterm-256color', r.Output) = 0 then Fail('T7 environment', 'got ' + r.Output)
  else Pass('T7 environment');
end;

procedure T8;
var
  r: TRun;
  s: string;
begin
  { tty_nr alone does not tell: without setsid the shell keeps ptytest's own terminal
    (WSL gives it one). /dev/tty is the controlling terminal: what is written there has
    to come out of this PTY. }
  r := Run('cut -d'' '' -f7 /proc/$$/stat; echo tyterm-$((6*7)) > /dev/tty', 1048576, 0, False);
  s := Trim(Copy(r.Output, 1, Pos(#10, r.Output + #10) - 1));
  if (s = '') or (s = '0') then Fail('T8 controlling tty', 'tty_nr "' + s + '"')
  else if Pos('tyterm-42', r.Output) = 0 then Fail('T8 controlling tty', '/dev/tty is not this PTY')
  else Pass('T8 controlling tty (tty_nr ' + s + ')');
end;

{ A child that ignores the hang-up keeps the slave open: only the wake-up pipe gets
  the reader out, and the kill after a second the child }
procedure T10;
var
  s: TPtySession;
  b: TUnixPtyBackend;
  err: string;
  pid: TPid;
  t0, took: QWord;
begin
  b := TUnixPtyBackend.Create;
  s := TPtySession.Create(b);
  try
    if not s.Start('trap '''' HUP; sleep 100', 80, 24, err) then
    begin
      Fail('T10 close, hang-up ignored', err);
      Exit;
    end;
    pid := b.Pid;
    Sleep(300);
    t0 := GetTickCount64;
    s.Close;
    took := GetTickCount64 - t0;
    if took > 200 then Fail('T10 close, hang-up ignored', Format('Close took %d ms', [took]))
    else if not PtyWaitForFinishers(PtyExitWaitMs) then Fail('T10 close, hang-up ignored', 'the finisher did not finish')
    else if (FpKill(pid, 0) = 0) or (fpgeterrno <> ESysESRCH) then Fail('T10 close, hang-up ignored', 'the child is still there')
    else if GetTickCount64 - t0 < PtyCloseWaitMs then
      Fail('T10 close, hang-up ignored', Format('gone after %d ms: it did not ignore the hang-up', [GetTickCount64 - t0]))
    else Pass(Format('T10 close, hang-up ignored (%d ms, killed after %d ms)', [took, GetTickCount64 - t0]));
  finally
    s.Free;
  end;
end;

procedure T9;
var
  r: TRun;
begin
  r := Run('no-such-command-tyterm', 1048576, 0, False);
  if not r.Ended then Fail('T9 no such command', 'no end')
  else if r.Code <> 127 then Fail('T9 no such command', 'code ' + IntToStr(r.Code))
  else Pass('T9 no such command');
end;

{ macOS answers POLLNVAL for a pty's master; the select path, forced, on Linux }
procedure T11;
const
  N = 300000;
var
  r: TRun;
begin
  r := Run('echo tyterm-select; head -c 300000 /dev/zero | tr ''\0'' x', 65536, 5, False, 30000, True);
  if not r.Ended then Fail('T11 select', 'no end: ' + r.Error)
  else if Pos('tyterm-select', r.Output) = 0 then Fail('T11 select', 'got ' + Copy(r.Output, 1, 80))
  else if CountOf('x', r.Output) <> N then Fail('T11 select', Format('%d x of %d', [CountOf('x', r.Output), N]))
  else if r.Code <> 0 then Fail('T11 select', 'code ' + IntToStr(r.Code))
  else Pass('T11 select');
end;

{ what the child must not inherit: this program ignores SIGPIPE, blocks SIGUSR2 on the
  forking thread and holds a descriptor without close-on-exec -- the child's shell has
  none of the three, and `yes | head -1` ends the way it should (yes dies of SIGPIPE,
  says nothing). The mask is only a weak check here: Ubuntu's /bin/sh is dash, which
  clears its signal mask itself when it starts; a shell that does not (bash as /bin/sh)
  shows the child's own reset. }
procedure T12;
var
  r: TRun;
  ign, old: SigActionRec;
  blk, oldMask: TSigSet;
  fd: cint;
  cmd: string;
begin
  FillChar(ign, SizeOf(ign), 0);
  ign.sa_handler := SigActionHandler(SIG_IGN);
  FpSigAction(SIGPIPE, @ign, @old);
  FpSigEmptySet(blk);
  FpSigAddSet(blk, SIGUSR2);
  FpSigProcMask(SIG_BLOCK, @blk, @oldMask);
  fd := FpOpen('/dev/null', O_RDONLY);
  try
    cmd := Format('grep -E "^Sig(Blk|Ign)" /proc/self/status; ' +
      'if [ -e /proc/$$/fd/%d ]; then echo fd-leaked; else echo fd-closed; fi; yes | head -1', [fd]);
    r := Run(cmd, 1048576, 0, False);
  finally
    FpClose(fd);
    FpSigProcMask(SIG_SETMASK, @oldMask, nil);
    FpSigAction(SIGPIPE, @old, nil);
  end;
  if not r.Ended then Fail('T12 child state', 'no end: ' + r.Error)
  else if Pos('SigBlk:'#9'0000000000000000', r.Output) = 0 then Fail('T12 child state', 'mask: ' + r.Output)
  else if Pos('SigIgn:'#9'0000000000000000', r.Output) = 0 then Fail('T12 child state', 'ignored: ' + r.Output)
  else if Pos('fd-closed', r.Output) = 0 then Fail('T12 child state', 'descriptor: ' + r.Output)
  else if Pos('Broken pipe', r.Output) > 0 then Fail('T12 child state', 'yes saw EPIPE: ' + r.Output)
  else if r.Code <> 0 then Fail('T12 child state', 'code ' + IntToStr(r.Code))
  else Pass('T12 child state');
end;

begin
  Passed := 0;
  Failed := 0;
  T1;
  T2;
  T3;
  T4;
  T5;
  T6;
  T7;
  T8;
  T9;
  T10;
  T11;
  T12;
  WriteLn(Format('ptytest: %d passed, %d failed', [Passed, Failed]));
  Halt(Failed);
end.
