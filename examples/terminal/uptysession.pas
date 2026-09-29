unit uptysession;

{ A PTY session for the terminal example: one platform backend (uptywin: ConPTY,
  uptyunix: posix_openpt), a reader thread, a writer thread, and the flow control
  between the reader and the terminal.

  Threads (the terminal's rule, design spec 3.5: the terminal and its core are touched
  on the main thread only):
    - the READER blocks in Backend.Read and appends what it gets to a locked queue.
      When the queue goes from empty to not empty (or the program is gone) it calls
      OnWake -- once per batch, not once per read. OnWake runs on the reader thread;
      the host schedules a Pump on the main thread there (Application.QueueAsyncCall).
    - the WRITER blocks until keys are queued (Write, main thread) and writes them to
      the PTY, so a large paste never stalls the window.
    - the main thread Pumps the queue into the terminal and reports back, through
      Delivered, how much the terminal has parsed (its Write callbacks). Above the high
      water mark of bytes read but not yet parsed the reader stops reading, and goes on
      below the low one: the program is held back by the PTY instead of the terminal's
      queue growing (spec 12.3).

  CLOSING NEVER WAITS ON THE MAIN THREAD. Taking a program down can take seconds: before
  Windows 11 24H2 ClosePseudoConsole blocks until the console's output is drained and its
  program has gone (a program may sit in its close handler for five seconds), a Unix
  child may ignore the hang-up. So Close does only what is quick -- the reader starts
  discarding, the writer stops, OnWake is cleared (no wake reaches the host after Close
  returns), the backend is told to begin (BeginClose: ConPTY signals its exit waiter,
  which calls ClosePseudoConsole; Unix sends SIGHUP) -- and hands the rest to a finisher
  thread of its own: it waits for the program's side to go (PtyCloseWaitMs), ends the
  program by its handle / SIGKILL if not (PtyKillWaitMs more), interrupts the two
  threads until they are gone (PtyThreadsWaitMs), closes the handles and frees what the
  session used. The reader keeps reading (and discarding) all along: the pseudo console
  may wait for its output to be read before it closes. Anything that would not stop in
  time is left running together with everything it uses -- a leak (PtySessionsLeaked),
  never a hang or a use after free.

  The session object itself is only a handle: freeing it is Close, returns at once, and
  never frees what a thread still uses. A program that exits waits for the finishers
  with PtyWaitForFinishers (bounded) before it goes.

  Only Classes, SysUtils, SyncObjs: the WSL console test (tools/terminal-ptytest) runs
  it without the LCL. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, SyncObjs;

type
  { how BeginClose / FinishClose ended }
  TPtyCloseResult = (pcrGone, pcrKilled, pcrStuck);

  { One platform's PTY. Read and Write are called on the session's threads and block;
    Start, Resize and BeginClose on the main thread; FinishClose, Interrupt and Shutdown
    on the session's finisher thread. }
  TPtyBackend = class
  public
    function Start(const ACommand: string; ACols, ARows: Integer; out AError: string): Boolean; virtual; abstract;
    { > 0 the bytes read; <= 0 the end (the program's side closed, or Interrupt) }
    function Read(var ABuf; ACount: Integer): Integer; virtual; abstract;
    { True once everything is written; False = the pipe is broken, closing or Interrupt }
    function Write(const ABuf; ACount: Integer): Boolean; virtual; abstract;
    procedure Resize(ACols, ARows: Integer); virtual; abstract;
    { main thread, must not block: begin taking the program down. A blocked Write
      returns; Read goes on until the program's side closes (the default: Interrupt) }
    procedure BeginClose; virtual;
    { the finisher: wait for the program's side to go, at most AWaitMs; if it does not,
      end the program (by its handle, SIGKILL) and wait a bounded while more. pcrStuck:
      something still blocks and what the backend uses must not be freed. Default:
      pcrGone at once. }
    function FinishClose(AWaitMs: Integer): TPtyCloseResult; virtual;
    { Makes a blocked Read / Write return (any thread; may be called again) }
    procedure Interrupt; virtual; abstract;
    { After the end was read: the program's exit code (waiting for it at most AWaitMs;
      -1 = not known). Int64: a Windows code is a DWORD, and 4294967295 is not -1. }
    function ExitCode(AWaitMs: Integer): Int64; virtual; abstract;
    { the finisher, once both threads are gone: reap the program, close handles }
    procedure Shutdown; virtual; abstract;
    { The Windows backend answers (True, build) -- the core wants it (spec 12.4) }
    function IsConPty(out ABuild: Integer): Boolean; virtual;
    { The session started its threads (the Windows backend cancels their I/O to interrupt) }
    procedure BindThreads(AReader, AWriter: TThread); virtual;
  end;

  TPtySessionCore = class;

  { what a started session is made of; owned by the TPtySession until Close, by the
    finisher after. Not for the host. }
  TPtyThread = class(TThread)
  private
    FCore: TPtySessionCore;
    FReader: Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(ACore: TPtySessionCore; AReader: Boolean);
  end;

  TPtySessionCore = class
  private
    FBackend: TPtyBackend;
    FHigh, FLow, FChunk: Integer;
    FLock: TCriticalSection;
    FWakeLock: TCriticalSection;
    FResume: TEvent;
    FWriteEvent: TEvent;
    FData: RawByteString;
    FWriteQueue: RawByteString;
    FOutstanding, FMaxOutstanding, FTotalDelivered: Int64;
    FHeld: Boolean;
    FEnded, FEndReported: Boolean;
    FExitCode: Int64;
    FDiscard, FStopping, FWriterGone: Boolean;
    FReader, FWriter: TPtyThread;
    FWakeCount: Integer;
    FOnWake: TNotifyEvent;
    FStarted: Boolean;
    procedure ReadLoop;
    procedure WriteLoop;
    procedure ReaderEnded;
    procedure WriterEnded;
    procedure Wake;
    function ThreadsFinished: Boolean;
  public
    constructor Create(ABackend: TPtyBackend; AHigh, ALow, AChunk: Integer);
    destructor Destroy; override;
    function Start(const ACommand: string; ACols, ARows: Integer; out AError: string): Boolean;
    procedure Write(const AData: RawByteString);
    function Pump(out AData: RawByteString; out AExited: Boolean; out AExitCode: Int64): Boolean;
    procedure Delivered(ACount: Integer);
    { main thread, quick: discard, stop the writer, no more wakes, BeginClose }
    procedure BeginClose;
    { the finisher: the rest; True = everything stopped and may be freed }
    function Finish: Boolean;
    procedure SetOnWake(AValue: TNotifyEvent);
  end;

  { The host's handle on a session. }
  TPtySession = class
  private
    FCore: TPtySessionCore;
    FBackend: TPtyBackend;           { what the test properties read before Close }
    FStarted, FClosed: Boolean;
    FOnWake: TNotifyEvent;
    procedure SetOnWake(AValue: TNotifyEvent);
    function GetOutstanding: Int64;
    function GetMaxOutstanding: Int64;
    function GetWakeCount: Integer;
    function GetTotalDelivered: Int64;
    function GetPendingWrite: Integer;
    function GetWriterGone: Boolean;
  public
    { takes ABackend over }
    constructor Create(ABackend: TPtyBackend; AHigh: Integer = 1048576; ALow: Integer = 262144;
      AChunk: Integer = 65536);
    destructor Destroy; override;                 { Close; returns at once }
    function Start(const ACommand: string; ACols, ARows: Integer; out AError: string): Boolean;
    { main thread: queue keys for the writer (dropped once the writer is gone) }
    procedure Write(const AData: RawByteString);
    { main thread: straight to the backend }
    procedure Resize(ACols, ARows: Integer);
    { main thread: everything read so far; AExited once the end was read and everything
      before it handed out (reported once) }
    function Pump(out AData: RawByteString; out AExited: Boolean; out AExitCode: Int64): Boolean;
    { main thread: the terminal parsed ACount bytes (its Write callback) }
    procedure Delivered(ACount: Integer);
    { idempotent, returns at once (unit header): after it the session does nothing and
      OnWake is never called again; its threads and program are finished elsewhere }
    procedure Close;
    { called on the READER thread: the queue went from empty to not empty, or the end
      was read. The host schedules Pump on the main thread from here. Set before Start. }
    property OnWake: TNotifyEvent read FOnWake write SetOnWake;
    { FOR THE TESTS (0 / nil after Close) }
    property Outstanding: Int64 read GetOutstanding;           { read, not yet Delivered }
    property MaxOutstanding: Int64 read GetMaxOutstanding;
    property TotalDelivered: Int64 read GetTotalDelivered;
    property WakeCount: Integer read GetWakeCount;
    property PendingWrite: Integer read GetPendingWrite;       { queued, not yet taken by the writer }
    property WriterGone: Boolean read GetWriterGone;
    property Backend: TPtyBackend read FBackend;
    property Started: Boolean read FStarted;
    property Closed: Boolean read FClosed;
  end;

const
  { ms, the finisher's bounds (unit header): the program's side to go by itself, then
    after it was ended, then the two threads; PtyExitWaitMs covers all three }
  PtyCloseWaitMs = 3000;
  PtyKillWaitMs = 2000;
  PtyThreadsWaitMs = 3000;
  PtyThreadsStepMs = 20;
  PtyExitWaitMs = PtyCloseWaitMs + PtyKillWaitMs + PtyThreadsWaitMs + 1000;

{ sessions whose finisher has not finished yet }
function PtyFinishersRunning: Integer;
{ started sessions not freed yet: running, finishing, or leaked }
function PtySessionsAlive: Integer;
{ sessions whose threads or program would not stop: left running, not freed }
function PtySessionsLeaked: Integer;
{ any thread: wait until no finisher runs, at most AWaitMs; True = none left. A program
  calls it once as it exits. }
function PtyWaitForFinishers(AWaitMs: Integer): Boolean;

implementation

var
  GFinishers, GAlive, GLeaked: LongInt;

function PtyFinishersRunning: Integer;
begin
  Result := InterLockedExchangeAdd(GFinishers, 0);
end;

function PtySessionsAlive: Integer;
begin
  Result := InterLockedExchangeAdd(GAlive, 0);
end;

function PtySessionsLeaked: Integer;
begin
  Result := InterLockedExchangeAdd(GLeaked, 0);
end;

function PtyWaitForFinishers(AWaitMs: Integer): Boolean;
var
  t0: QWord;
begin
  t0 := GetTickCount64;
  while PtyFinishersRunning > 0 do
  begin
    if GetTickCount64 - t0 >= QWord(AWaitMs) then Exit(False);
    Sleep(10);
  end;
  Result := True;
end;

type
  TPtyFinisher = class(TThread)
  private
    FCore: TPtySessionCore;
  protected
    procedure Execute; override;
  public
    constructor Create(ACore: TPtySessionCore);
  end;

{ ---- TPtyBackend ------------------------------------------------------------------- }

procedure TPtyBackend.BeginClose;
begin
  Interrupt;
end;

function TPtyBackend.FinishClose(AWaitMs: Integer): TPtyCloseResult;
begin
  Result := pcrGone;
end;

function TPtyBackend.IsConPty(out ABuild: Integer): Boolean;
begin
  ABuild := 0;
  Result := False;
end;

procedure TPtyBackend.BindThreads(AReader, AWriter: TThread);
begin
end;

{ ---- TPtyThread -------------------------------------------------------------------- }

constructor TPtyThread.Create(ACore: TPtySessionCore; AReader: Boolean);
begin
  FCore := ACore;
  FReader := AReader;
  FreeOnTerminate := False;
  inherited Create(True);
end;

procedure TPtyThread.Execute;
begin
  try
    if FReader then
      FCore.ReadLoop
    else
      FCore.WriteLoop;
  except
    { a thread must not take the process down; what it leaves is reported below }
  end;
  if FReader then
    FCore.ReaderEnded
  else
    FCore.WriterEnded;
end;

{ ---- TPtyFinisher ------------------------------------------------------------------ }

constructor TPtyFinisher.Create(ACore: TPtySessionCore);
begin
  FCore := ACore;
  FreeOnTerminate := True;
  inherited Create(True);
  { counted before it can run (and uncount itself) }
  InterLockedIncrement(GFinishers);
  Start;
end;

procedure TPtyFinisher.Execute;
begin
  try
    try
      if FCore.Finish then
        FCore.Free
      else
        InterLockedIncrement(GLeaked);
    except
      InterLockedIncrement(GLeaked);
    end;
  finally
    InterLockedDecrement(GFinishers);
  end;
end;

{ ---- TPtySessionCore --------------------------------------------------------------- }

constructor TPtySessionCore.Create(ABackend: TPtyBackend; AHigh, ALow, AChunk: Integer);
begin
  inherited Create;
  FBackend := ABackend;
  FHigh := AHigh;
  FLow := ALow;
  FChunk := AChunk;
  if FChunk < 1 then FChunk := 1;
  FExitCode := -1;
  FLock := TCriticalSection.Create;
  FWakeLock := TCriticalSection.Create;
  FResume := TEvent.Create(nil, False, False, '');
  FWriteEvent := TEvent.Create(nil, False, False, '');
  InterLockedIncrement(GAlive);
end;

destructor TPtySessionCore.Destroy;
begin
  { only ever with both threads gone (Finish), or never started }
  FreeAndNil(FReader);
  FreeAndNil(FWriter);
  if FStarted then
    FBackend.Shutdown;
  FreeAndNil(FBackend);
  FreeAndNil(FResume);
  FreeAndNil(FWriteEvent);
  FreeAndNil(FWakeLock);
  FreeAndNil(FLock);
  InterLockedDecrement(GAlive);
  inherited Destroy;
end;

function TPtySessionCore.Start(const ACommand: string; ACols, ARows: Integer; out AError: string): Boolean;
begin
  Result := False;
  if not FBackend.Start(ACommand, ACols, ARows, AError) then
    Exit;
  FStarted := True;
  FReader := TPtyThread.Create(Self, True);
  FWriter := TPtyThread.Create(Self, False);
  FBackend.BindThreads(FReader, FWriter);
  FReader.Start;
  FWriter.Start;
  Result := True;
end;

procedure TPtySessionCore.SetOnWake(AValue: TNotifyEvent);
begin
  FWakeLock.Enter;
  try
    FOnWake := AValue;
  finally
    FWakeLock.Leave;
  end;
end;

procedure TPtySessionCore.Wake;
begin
  InterLockedIncrement(FWakeCount);
  { under a lock of its own (not FLock: the host's callback may take locks of its own):
    BeginClose clears OnWake under it, so once Close returns no callback is running or
    will run -- the host may go }
  FWakeLock.Enter;
  try
    if Assigned(FOnWake) then
      FOnWake(nil);
  finally
    FWakeLock.Leave;
  end;
end;

procedure TPtySessionCore.ReadLoop;
var
  buf: array of Byte;
  n: Integer;
  code: Int64;
  wasEmpty, discard: Boolean;
  s: RawByteString;
begin
  SetLength(buf, FChunk);
  while True do
  begin
    { back-pressure: above the high water mark wait for the terminal to catch up to
      below the low one; every 100 ms look whether the session is closing }
    FLock.Enter;
    try
      if not FDiscard and (FOutstanding > FHigh) then
        FHeld := True;
    finally
      FLock.Leave;
    end;
    while True do
    begin
      FLock.Enter;
      try
        if FDiscard or not FHeld then Break;
      finally
        FLock.Leave;
      end;
      FResume.WaitFor(100);
    end;
    n := FBackend.Read(buf[0], FChunk);
    FLock.Enter;
    try
      discard := FDiscard;
    finally
      FLock.Leave;
    end;
    if n <= 0 then
    begin
      { the end: the program's code (not while closing -- nobody waits for it) }
      if discard then
        code := -1
      else
        code := FBackend.ExitCode(2000);
      FLock.Enter;
      try
        FEnded := True;
        FExitCode := code;
      finally
        FLock.Leave;
      end;
      Wake;
      Exit;
    end;
    { closing: read on (the pseudo console may wait for its output to be drained),
      keep nothing }
    if discard then
      Continue;
    SetLength(s, n);
    Move(buf[0], s[1], n);
    FLock.Enter;
    try
      wasEmpty := FData = '';
      FData := FData + s;
      Inc(FOutstanding, n);
      if FOutstanding > FMaxOutstanding then
        FMaxOutstanding := FOutstanding;
    finally
      FLock.Leave;
    end;
    if wasEmpty then
      Wake;
  end;
end;

{ the reader is gone however it went: an exception in it is an end too, and the host
  hears about it (the exit line), with the code not known }
procedure TPtySessionCore.ReaderEnded;
var
  unreported: Boolean;
begin
  FLock.Enter;
  try
    unreported := not FEnded;
    if unreported then
    begin
      FEnded := True;
      FExitCode := -1;
    end;
  finally
    FLock.Leave;
  end;
  if unreported then
    Wake;
end;

procedure TPtySessionCore.WriteLoop;
var
  data: RawByteString;
  stop: Boolean;
begin
  while True do
  begin
    FWriteEvent.WaitFor(100);
    FLock.Enter;
    try
      stop := FStopping;
      data := FWriteQueue;
      FWriteQueue := '';
    finally
      FLock.Leave;
    end;
    if stop then
      Exit;
    if data <> '' then
      if not FBackend.Write(data[1], Length(data)) then
        Exit;                                    { broken: the reader will read the end }
  end;
end;

{ nothing writes the queue out any more: Write stops adding to it }
procedure TPtySessionCore.WriterEnded;
begin
  FLock.Enter;
  try
    FWriterGone := True;
    FWriteQueue := '';
  finally
    FLock.Leave;
  end;
end;

procedure TPtySessionCore.Write(const AData: RawByteString);
begin
  FLock.Enter;
  try
    if FWriterGone or FStopping then Exit;
    FWriteQueue := FWriteQueue + AData;
  finally
    FLock.Leave;
  end;
  FWriteEvent.SetEvent;
end;

function TPtySessionCore.Pump(out AData: RawByteString; out AExited: Boolean; out AExitCode: Int64): Boolean;
begin
  FLock.Enter;
  try
    AData := FData;
    FData := '';
    AExited := FEnded and not FEndReported;
    if AExited then
      FEndReported := True;
    AExitCode := FExitCode;
  finally
    FLock.Leave;
  end;
  Result := (AData <> '') or AExited;
end;

procedure TPtySessionCore.Delivered(ACount: Integer);
begin
  FLock.Enter;
  try
    Dec(FOutstanding, ACount);
    Inc(FTotalDelivered, ACount);
    if FHeld and (FOutstanding < FLow) then
    begin
      FHeld := False;
      FResume.SetEvent;
    end;
  finally
    FLock.Leave;
  end;
end;

function TPtySessionCore.ThreadsFinished: Boolean;
begin
  Result := ((FReader = nil) or FReader.Finished) and ((FWriter = nil) or FWriter.Finished);
end;

procedure TPtySessionCore.BeginClose;
begin
  { 1. the reader discards and no longer waits for the terminal; the writer stops }
  FLock.Enter;
  try
    FDiscard := True;
    FStopping := True;
    FHeld := False;
    FWriteQueue := '';
  finally
    FLock.Leave;
  end;
  { 2. no wake reaches the host from here on (Wake holds this lock while it calls) }
  SetOnWake(nil);
  FResume.SetEvent;
  FWriteEvent.SetEvent;
  { 3. the program's side begins to go -- nothing here blocks }
  FBackend.BeginClose;
end;

function TPtySessionCore.Finish: Boolean;
var
  closeResult: TPtyCloseResult;
  t0: QWord;
begin
  { 1. the program's side goes, or is ended; the reader drains meanwhile }
  closeResult := FBackend.FinishClose(PtyCloseWaitMs);
  { 2. interrupt until both threads are gone -- a cancel that lands between two calls
    is lost, so it is repeated -- bounded }
  FBackend.Interrupt;
  t0 := GetTickCount64;
  while not ThreadsFinished and (GetTickCount64 - t0 < PtyThreadsWaitMs) do
  begin
    Sleep(PtyThreadsStepMs);
    FBackend.Interrupt;
  end;
  { 3. only what nothing uses any more is freed (the caller frees, Destroy closes the
    handles); the rest stays -- a leak, not a use after free }
  Result := ThreadsFinished and (closeResult <> pcrStuck);
  if Result then
  begin
    FReader.WaitFor;
    FWriter.WaitFor;
  end;
end;

{ ---- TPtySession ------------------------------------------------------------------- }

constructor TPtySession.Create(ABackend: TPtyBackend; AHigh, ALow, AChunk: Integer);
begin
  inherited Create;
  FBackend := ABackend;
  FCore := TPtySessionCore.Create(ABackend, AHigh, ALow, AChunk);
end;

destructor TPtySession.Destroy;
begin
  Close;
  inherited Destroy;
end;

function TPtySession.Start(const ACommand: string; ACols, ARows: Integer; out AError: string): Boolean;
begin
  AError := '';
  Result := False;
  if FStarted or FClosed then
  begin
    AError := 'the session was started already';
    Exit;
  end;
  FCore.SetOnWake(FOnWake);
  if not FCore.Start(ACommand, ACols, ARows, AError) then
    Exit;
  FStarted := True;
  Result := True;
end;

procedure TPtySession.SetOnWake(AValue: TNotifyEvent);
begin
  FOnWake := AValue;
  if FCore <> nil then
    FCore.SetOnWake(AValue);
end;

procedure TPtySession.Write(const AData: RawByteString);
begin
  if (AData = '') or not FStarted or FClosed then Exit;
  FCore.Write(AData);
end;

procedure TPtySession.Resize(ACols, ARows: Integer);
begin
  if FStarted and not FClosed then
    FBackend.Resize(ACols, ARows);
end;

function TPtySession.Pump(out AData: RawByteString; out AExited: Boolean; out AExitCode: Int64): Boolean;
begin
  if not FStarted or FClosed then
  begin
    AData := '';
    AExited := False;
    AExitCode := -1;
    Exit(False);
  end;
  Result := FCore.Pump(AData, AExited, AExitCode);
end;

procedure TPtySession.Delivered(ACount: Integer);
begin
  if FStarted and not FClosed then
    FCore.Delivered(ACount);
end;

procedure TPtySession.Close;
var
  core: TPtySessionCore;
begin
  if FClosed then Exit;
  FClosed := True;
  core := FCore;
  FCore := nil;
  FBackend := nil;
  if core = nil then Exit;
  if not FStarted then
  begin
    core.Free;
    Exit;
  end;
  core.BeginClose;
  { from here the core belongs to the finisher }
  TPtyFinisher.Create(core);
end;

function TPtySession.GetOutstanding: Int64;
begin
  Result := 0;
  if FCore = nil then Exit;
  FCore.FLock.Enter;
  try
    Result := FCore.FOutstanding;
  finally
    FCore.FLock.Leave;
  end;
end;

function TPtySession.GetMaxOutstanding: Int64;
begin
  Result := 0;
  if FCore = nil then Exit;
  FCore.FLock.Enter;
  try
    Result := FCore.FMaxOutstanding;
  finally
    FCore.FLock.Leave;
  end;
end;

function TPtySession.GetWakeCount: Integer;
begin
  Result := 0;
  if FCore = nil then Exit;
  Result := InterLockedExchangeAdd(FCore.FWakeCount, 0);
end;

function TPtySession.GetTotalDelivered: Int64;
begin
  Result := 0;
  if FCore = nil then Exit;
  FCore.FLock.Enter;
  try
    Result := FCore.FTotalDelivered;
  finally
    FCore.FLock.Leave;
  end;
end;

function TPtySession.GetPendingWrite: Integer;
begin
  Result := 0;
  if FCore = nil then Exit;
  FCore.FLock.Enter;
  try
    Result := Length(FCore.FWriteQueue);
  finally
    FCore.FLock.Leave;
  end;
end;

function TPtySession.GetWriterGone: Boolean;
begin
  Result := False;
  if FCore = nil then Exit;
  FCore.FLock.Enter;
  try
    Result := FCore.FWriterGone;
  finally
    FCore.FLock.Leave;
  end;
end;

end.
