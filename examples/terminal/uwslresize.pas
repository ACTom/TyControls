unit uwslresize;

{ The pipe mode's window size for WSL (7 期验收反馈).

  A pipe carries bytes only: no resize goes down it. The example's WSL entry runs the login
  shell under script (util-linux), which gives it a PTY in Linux; the wrapper also writes
  the shell's PID and that PTY's name into a file of its own (%TTYFILE%,
  /tmp/tyterm-<our PID>-<n>.tty). When the terminal changes size, a short side process
  sets the PTY's size from outside:

    wsl.exe [-d D] [-u U] -e sh -c "read p t < F && [ $(readlink /proc/$p/fd/0) = $t ] && stty -F $t cols C rows R"

  -- the kernel then sends the foreground program SIGWINCH, as for any terminal. It only
  touches the PTY while the shell that wrote the file still has it as its input: a PTY
  number is used again once its terminal has gone. A side process takes about half a
  second (WSL starts one each time), so the sizes are debounced: sent 250 ms after the
  last change, one process at a time, the latest size after it (TWslResizeQueue, pure,
  the clock passed in). A failure is tried again a second later, three tries in all; then
  nothing until the next change. Failures are silent (a size that does not arrive is not
  worth a dialog).

  Only for the WSL entry: a command of wsl.exe that has %TTYFILE% in it (typed by hand
  too); the side process uses the same distribution and user (-d / --distribution, -u /
  --user). Not for ssh -tt: a real SSH client sends the new size in the SSH protocol's
  window-change message; on a pipe we only have the byte stream.

  TWslPipeBackend (Windows) is TProcessPipeBackend with this added; the side processes
  run on a thread of its own, never on the main thread, and are waited for there -- a
  side process that takes longer than WslSideWaitMs is ended by its handle, nothing is
  ended by name. BeginClose stops the sending (main thread, at once); the session's
  finisher stops the thread, then starts one more side process that removes the file
  (not waited for). The file is removed from our side, not by a trap in the wrapper: the
  wrapper execs the login shell (a trap would not survive the exec), and our side removes
  it however the Linux side ended. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils
  {$IFDEF MSWINDOWS}, Windows, SyncObjs, uptysession, uptywin{$ENDIF};

const
  { in the command: the file the wrapper writes the shell's PID and PTY into }
  WslTtyFilePlaceholder = '%TTYFILE%';
  WslResizeDebounceMs = 250;
  WslResizeRetryMs = 1000;
  WslResizeTries = 3;
  { a side process that takes longer is ended (by its handle) }
  WslSideWaitMs = 5000;

type
  { What to send, and when (pure: the clock is passed in). Starts at the size the shell
    started with. }
  TWslResizeQueue = class
  private
    FSentCols, FSentRows, FWantCols, FWantRows, FFlightCols, FFlightRows: Integer;
    FDueAt: QWord;
    FBusy, FStopped, FGaveUp: Boolean;
    FFailures: Integer;
  public
    constructor Create(ACols, ARows: Integer);
    { the terminal's new size: sent WslResizeDebounceMs after the last one }
    procedure SizeChanged(ACols, ARows: Integer; ANow: QWord);
    { True: send this size now (it is in flight until Done) }
    function Next(ANow: QWord; out ACols, ARows: Integer): Boolean;
    procedure Done(AOk: Boolean; ANow: QWord);
    { nothing is sent from here on }
    procedure Stop;
    property Busy: Boolean read FBusy;
    property Stopped: Boolean read FStopped;
    { three tries failed; the next change tries again }
    property GaveUp: Boolean read FGaveUp;
  end;

{ AExe: the command's wsl.exe as given; AOptions: its -d / -u options (' -d Ubuntu'). False
  when the command is not wsl.exe or has no %TTYFILE% }
function WslResizeTarget(const ACommand: string; out AExe, AOptions: string): Boolean;
function WslTtyFileName(AProcessId: Cardinal; ASeq: Integer): string;
function WslResizeCommand(const AExe, AOptions, ATtyFile: string; ACols, ARows: Integer): string;
function WslCleanupCommand(const AExe, AOptions, ATtyFile: string): string;

{$IFDEF MSWINDOWS}
type
  TWslPipeBackend = class;

  TWslResizeThread = class(TThread)
  private
    FOwner: TWslPipeBackend;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TWslPipeBackend);
  end;

  { the pipe backend; for the WSL entry, the size goes to the PTY in Linux as well }
  TWslPipeBackend = class(TProcessPipeBackend)
  private
    FLock: SyncObjs.TCriticalSection;
    FWake: SyncObjs.TEvent;
    FStop: THandle;                      { a Windows event: waited for with the process }
    FQueue: TWslResizeQueue;
    FThread: TWslResizeThread;
    FExe, FOptions, FTtyFile: string;
    FSent, FFailed: LongInt;
    FCleaned: Boolean;
    function ProgramGone: Boolean;
    procedure StopSending;
    procedure StopThread;
    procedure Cleanup;
    function RunSide(const ACommand: string; AWait: Boolean): Boolean;
  public
    constructor Create(AMergeStderr: Boolean = True);
    destructor Destroy; override;
    function Start(const ACommand: string; ACols, ARows: Integer; out AError: string): Boolean; override;
    procedure Resize(ACols, ARows: Integer); override;
    procedure BeginClose; override;
    function FinishClose(AWaitMs: Integer): TPtyCloseResult; override;
    procedure Shutdown; override;
    { FOR THE TESTS: the file ('' = no side channel), the side processes that set a
      size / did not }
    property TtyFile: string read FTtyFile;
    function ResizesSent: Integer;
    function ResizesFailed: Integer;
  end;
{$ENDIF}

implementation

{ ---- TWslResizeQueue ------------------------------------------------------------------ }

constructor TWslResizeQueue.Create(ACols, ARows: Integer);
begin
  inherited Create;
  FSentCols := ACols;
  FSentRows := ARows;
  FWantCols := ACols;
  FWantRows := ARows;
end;

procedure TWslResizeQueue.SizeChanged(ACols, ARows: Integer; ANow: QWord);
begin
  if FStopped then Exit;
  FWantCols := ACols;
  FWantRows := ARows;
  FDueAt := ANow + WslResizeDebounceMs;
  FFailures := 0;
  FGaveUp := False;
end;

function TWslResizeQueue.Next(ANow: QWord; out ACols, ARows: Integer): Boolean;
begin
  ACols := 0;
  ARows := 0;
  Result := not FStopped and not FBusy and not FGaveUp
    and ((FWantCols <> FSentCols) or (FWantRows <> FSentRows)) and (ANow >= FDueAt);
  if not Result then Exit;
  FBusy := True;
  FFlightCols := FWantCols;
  FFlightRows := FWantRows;
  ACols := FFlightCols;
  ARows := FFlightRows;
end;

procedure TWslResizeQueue.Done(AOk: Boolean; ANow: QWord);
begin
  if not FBusy then Exit;
  FBusy := False;
  if AOk then
  begin
    FSentCols := FFlightCols;
    FSentRows := FFlightRows;
    FFailures := 0;
    Exit;
  end;
  Inc(FFailures);
  if FFailures >= WslResizeTries then
    FGaveUp := True
  else if FDueAt < ANow + WslResizeRetryMs then
    FDueAt := ANow + WslResizeRetryMs;
end;

procedure TWslResizeQueue.Stop;
begin
  FStopped := True;
end;

{ ---- the commands ------------------------------------------------------------------- }

{ a command line's arguments, as Windows programs read them in the common cases (spaces
  outside double quotes separate, the quotes go) }
function SplitArgs(const S: string): TStringArray;
var
  i: Integer;
  cur: string;
  quoted, any: Boolean;

  procedure Push;
  begin
    if any then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := cur;
    end;
    cur := '';
    any := False;
  end;

begin
  Result := nil;
  cur := '';
  quoted := False;
  any := False;
  for i := 1 to Length(S) do
    if S[i] = '"' then
    begin
      quoted := not quoted;
      any := True;
    end
    else if (S[i] in [' ', #9]) and not quoted then
      Push
    else
    begin
      cur := cur + S[i];
      any := True;
    end;
  Push;
end;

function QuoteArg(const S: string): string;
begin
  if (S = '') or (Pos(' ', S) > 0) then
    Result := '"' + S + '"'
  else
    Result := S;
end;

function WslResizeTarget(const ACommand: string; out AExe, AOptions: string): Boolean;
var
  args: TStringArray;
  i: Integer;
  a, name: string;
begin
  AExe := '';
  AOptions := '';
  Result := False;
  if Pos(WslTtyFilePlaceholder, ACommand) = 0 then Exit;
  args := SplitArgs(ACommand);
  if Length(args) = 0 then Exit;
  name := LowerCase(ExtractFileName(StringReplace(args[0], '\', '/', [rfReplaceAll])));
  if (name <> 'wsl.exe') and (name <> 'wsl') then Exit;
  i := 1;
  while i <= High(args) do
  begin
    a := args[i];
    if (a = '-e') or (a = '--exec') or (a = '--') then Break;
    if ((a = '-d') or (a = '--distribution') or (a = '-u') or (a = '--user')) and (i < High(args)) then
    begin
      AOptions := AOptions + ' ' + a + ' ' + QuoteArg(args[i + 1]);
      Inc(i, 2);
    end
    else if (a = '--cd') and (i < High(args)) then
      Inc(i, 2)
    else
      Inc(i);
  end;
  AExe := QuoteArg(args[0]);
  Result := True;
end;

function WslTtyFileName(AProcessId: Cardinal; ASeq: Integer): string;
begin
  Result := Format('/tmp/tyterm-%d-%d.tty', [AProcessId, ASeq]);
end;

function WslResizeCommand(const AExe, AOptions, ATtyFile: string; ACols, ARows: Integer): string;
begin
  Result := Format('%s%s -e sh -c "read p t < %s && [ $(readlink /proc/$p/fd/0) = $t ] && stty -F $t cols %d rows %d"',
    [AExe, AOptions, ATtyFile, ACols, ARows]);
end;

function WslCleanupCommand(const AExe, AOptions, ATtyFile: string): string;
begin
  Result := AExe + AOptions + ' -e rm -f ' + ATtyFile;
end;

{$IFDEF MSWINDOWS}

{ ---- TWslPipeBackend ------------------------------------------------------------------ }

const
  CREATE_NO_WINDOW_ = $08000000;

var
  GTtySeq: LongInt = 0;

constructor TWslResizeThread.Create(AOwner: TWslPipeBackend);
begin
  FOwner := AOwner;
  inherited Create(False);
end;

procedure TWslResizeThread.Execute;
var
  c, r: Integer;
  due, ok: Boolean;
begin
  while not Terminated do
  begin
    FOwner.FWake.WaitFor(50);
    if Terminated then Break;
    { the shell has gone: its PTY is not ours to size any more }
    if FOwner.ProgramGone then
      FOwner.StopSending;
    FOwner.FLock.Enter;
    try
      due := FOwner.FQueue.Next(GetTickCount64, c, r);
    finally
      FOwner.FLock.Leave;
    end;
    if not due then Continue;
    ok := FOwner.RunSide(WslResizeCommand(FOwner.FExe, FOwner.FOptions, FOwner.FTtyFile, c, r), True);
    if ok then
      InterLockedIncrement(FOwner.FSent)
    else
      InterLockedIncrement(FOwner.FFailed);
    FOwner.FLock.Enter;
    try
      FOwner.FQueue.Done(ok, GetTickCount64);
    finally
      FOwner.FLock.Leave;
    end;
  end;
end;

constructor TWslPipeBackend.Create(AMergeStderr: Boolean);
begin
  inherited Create(AMergeStderr);
  FLock := SyncObjs.TCriticalSection.Create;
  FWake := SyncObjs.TEvent.Create(nil, False, False, '');
  FStop := CreateEvent(nil, True, False, nil);
end;

destructor TWslPipeBackend.Destroy;
begin
  { Shutdown: the thread stopped, the file's removal started }
  inherited Destroy;
  FQueue.Free;
  if FStop <> 0 then
    CloseHandle(FStop);
  FWake.Free;
  FLock.Free;
end;

function TWslPipeBackend.Start(const ACommand: string; ACols, ARows: Integer; out AError: string): Boolean;
var
  cmd: string;
begin
  cmd := ACommand;
  FTtyFile := '';
  if WslResizeTarget(ACommand, FExe, FOptions) then
  begin
    FTtyFile := WslTtyFileName(GetCurrentProcessId, InterLockedIncrement(GTtySeq));
    cmd := StringReplace(cmd, WslTtyFilePlaceholder, FTtyFile, [rfReplaceAll]);
  end;
  Result := inherited Start(cmd, ACols, ARows, AError);
  if not Result then
  begin
    FTtyFile := '';
    Exit;
  end;
  if FTtyFile <> '' then
  begin
    FQueue := TWslResizeQueue.Create(ACols, ARows);
    FThread := TWslResizeThread.Create(Self);
  end;
end;

procedure TWslPipeBackend.Resize(ACols, ARows: Integer);
begin
  if FThread = nil then Exit;
  FLock.Enter;
  try
    FQueue.SizeChanged(ACols, ARows, GetTickCount64);
  finally
    FLock.Leave;
  end;
  FWake.SetEvent;
end;

function TWslPipeBackend.ProgramGone: Boolean;
begin
  Result := ExitCode(0) <> -1;
end;

procedure TWslPipeBackend.StopSending;
begin
  if FQueue = nil then Exit;
  FLock.Enter;
  try
    FQueue.Stop;
  finally
    FLock.Leave;
  end;
end;

procedure TWslPipeBackend.BeginClose;
begin
  { main thread, at once: nothing is sent from here on; a side process in flight is
    left to finish on its own }
  StopSending;
  SetEvent(FStop);
  FWake.SetEvent;
  inherited BeginClose;
end;

procedure TWslPipeBackend.StopThread;
begin
  if FThread = nil then Exit;
  StopSending;
  SetEvent(FStop);
  FThread.Terminate;
  FWake.SetEvent;
  FThread.WaitFor;
  FreeAndNil(FThread);
end;

procedure TWslPipeBackend.Cleanup;
begin
  if (FTtyFile = '') or FCleaned then Exit;
  FCleaned := True;
  RunSide(WslCleanupCommand(FExe, FOptions, FTtyFile), False);
end;

function TWslPipeBackend.FinishClose(AWaitMs: Integer): TPtyCloseResult;
begin
  Result := inherited FinishClose(AWaitMs);
  StopThread;
  Cleanup;
end;

procedure TWslPipeBackend.Shutdown;
begin
  StopThread;
  Cleanup;
  inherited Shutdown;
end;

{ A side process, no window, no handles of ours. AWait: wait for it (at most
  WslSideWaitMs, then it is ended by its handle; a stop ends the wait and leaves it to
  finish); True = it ended with 0. Not waited: True = it started. }
function TWslPipeBackend.RunSide(const ACommand: string; AWait: Boolean): Boolean;
var
  si: TStartupInfoW;
  pi: TProcessInformation;
  cmd: UnicodeString;
  hs: array[0..1] of THandle;
  code: DWORD;
begin
  Result := False;
  FillChar(si, SizeOf(si), 0);
  si.cb := SizeOf(si);
  FillChar(pi, SizeOf(pi), 0);
  cmd := UTF8Decode(ACommand);
  UniqueString(cmd);
  if not CreateProcessW(nil, PWideChar(cmd), nil, nil, False, CREATE_NO_WINDOW_, nil, nil, si, pi) then
    Exit;
  CloseHandle(pi.hThread);
  try
    if not AWait then
      Exit(True);
    hs[0] := pi.hProcess;
    hs[1] := FStop;
    case WaitForMultipleObjects(2, @hs[0], False, WslSideWaitMs) of
      WAIT_OBJECT_0:
        begin
          code := 1;
          Result := GetExitCodeProcess(pi.hProcess, code) and (code = 0);
        end;
      WAIT_TIMEOUT:
        TerminateProcess(pi.hProcess, 1);
    end;
  finally
    CloseHandle(pi.hProcess);
  end;
end;

function TWslPipeBackend.ResizesSent: Integer;
begin
  Result := InterLockedExchangeAdd(FSent, 0);
end;

function TWslPipeBackend.ResizesFailed: Integer;
begin
  Result := InterLockedExchangeAdd(FFailed, 0);
end;

{$ENDIF}

end.
