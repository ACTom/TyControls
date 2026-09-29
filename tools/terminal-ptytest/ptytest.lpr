program ptytest;

{ The terminal example's Unix PTY backend (examples/terminal/uptyunix + uptysession),
  run as a plain FPC console program: no LCL, no package. Built and run in WSL:

    cd tools/terminal-ptytest && mkdir -p lib && \
      fpc -Mobjfpc -Sh -FUlib -Fu../../examples/terminal -optytest ptytest.lpr && ./ptytest

  Each case starts a command through the session, pumps its output on the main thread
  (woken by the session's OnWake, as the example is by QueueAsyncCall), counts it back
  with Delivered, and waits at most 10 s. Prints PASS / FAIL per case and, last,
  "ptytest: N passed, M failed"; the exit code is M. }

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
    Code: Integer;
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
  ATimeoutMs: Integer = 10000): TRun;
var
  waker: TWaker;
  s: TPtySession;
  data: RawByteString;
  exited: Boolean;
  code: Integer;
  t0: QWord;
begin
  Result := Default(TRun);
  Result.Code := -2;
  waker := TWaker.Create;
  s := TPtySession.Create(TUnixPtyBackend.Create, AHigh, AHigh div 4, 65536);
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
    try
      s.Close;
    except
      on E: Exception do
      begin
        Fail('T6 close', E.Message);
        Exit;
      end;
    end;
    took := GetTickCount64 - t0;
    if took > 2000 then Fail('T6 close', Format('%d ms', [took]))
    else if (FpKill(pid, 0) = 0) or (fpgeterrno <> ESysESRCH) then Fail('T6 close', 'the child is still there')
    else Pass(Format('T6 close (%d ms)', [took]));
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
  r := Run('cut -d'' '' -f7 /proc/$$/stat', 1048576, 0, False);
  s := Trim(r.Output);
  if (s = '') or (s = '0') then Fail('T8 controlling tty', 'tty_nr "' + s + '"')
  else Pass('T8 controlling tty (tty_nr ' + s + ')');
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
  WriteLn(Format('ptytest: %d passed, %d failed', [Passed, Failed]));
  Halt(Failed);
end.
