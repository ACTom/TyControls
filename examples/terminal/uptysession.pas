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
  Close is safe from any state: the reader is put in a discarding mode (it no longer
  waits for the terminal), the backend is interrupted until both threads are gone
  (each wait bounded), and only then are the handles closed. Nothing here waits on the
  main thread, so the main thread may wait on the threads.

  Only Classes, SysUtils, SyncObjs: the WSL console test (tools/terminal-ptytest) runs
  it without the LCL. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, SyncObjs;

type
  { One platform's PTY. Read and Write are called on the session's threads and block;
    the rest on the main thread. }
  TPtyBackend = class
  public
    function Start(const ACommand: string; ACols, ARows: Integer; out AError: string): Boolean; virtual; abstract;
    { > 0 the bytes read; <= 0 the end (the program's side closed, or Interrupt) }
    function Read(var ABuf; ACount: Integer): Integer; virtual; abstract;
    { True once everything is written; False = the pipe is broken or Interrupt }
    function Write(const ABuf; ACount: Integer): Boolean; virtual; abstract;
    procedure Resize(ACols, ARows: Integer); virtual; abstract;
    { Makes a blocked Read / Write return (any thread; may be called again) }
    procedure Interrupt; virtual; abstract;
    { After the end was read: the program's exit code (waiting for it at most AWaitMs;
      -1 = not known) }
    function ExitCode(AWaitMs: Integer): Integer; virtual; abstract;
    { Once both threads are gone, on the main thread: reap the program, close handles }
    procedure Shutdown; virtual; abstract;
    { The Windows backend answers (True, build) -- the core wants it (spec 12.4) }
    function IsConPty(out ABuild: Integer): Boolean; virtual;
    { The session started its reader (the Windows backend cancels its I/O to interrupt) }
    procedure BindReader(AThread: TThread); virtual;
  end;

  TPtySession = class;

  TPtyThread = class(TThread)
  private
    FSession: TPtySession;
    FReader: Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(ASession: TPtySession; AReader: Boolean);
  end;

  TPtySession = class
  private
    FBackend: TPtyBackend;
    FHigh, FLow, FChunk: Integer;
    FLock: TCriticalSection;
    FResume: TEvent;
    FWriteEvent: TEvent;
    FData: RawByteString;
    FWriteQueue: RawByteString;
    FOutstanding, FMaxOutstanding, FTotalDelivered: Int64;
    FHeld: Boolean;
    FEnded, FEndReported: Boolean;
    FExitCode: Integer;
    FDiscard, FStopping: Boolean;
    FReader, FWriter: TPtyThread;
    FWakeCount: Integer;
    FOnWake: TNotifyEvent;
    FStarted, FClosed: Boolean;
    procedure ReadLoop(AThread: TPtyThread);
    procedure WriteLoop(AThread: TPtyThread);
    procedure Wake;
    function GetOutstanding: Int64;
    function GetMaxOutstanding: Int64;
    function GetWakeCount: Integer;
    function GetTotalDelivered: Int64;
  public
    { takes ABackend over }
    constructor Create(ABackend: TPtyBackend; AHigh: Integer = 1048576; ALow: Integer = 262144;
      AChunk: Integer = 65536);
    destructor Destroy; override;                 { Close }
    function Start(const ACommand: string; ACols, ARows: Integer; out AError: string): Boolean;
    { main thread: queue keys for the writer }
    procedure Write(const AData: RawByteString);
    { main thread: straight to the backend }
    procedure Resize(ACols, ARows: Integer);
    { main thread: everything read so far; AExited once the end was read and everything
      before it handed out (reported once) }
    function Pump(out AData: RawByteString; out AExited: Boolean; out AExitCode: Integer): Boolean;
    { main thread: the terminal parsed ACount bytes (its Write callback) }
    procedure Delivered(ACount: Integer);
    { idempotent; raises if the threads do not stop within 5 s (never hangs) }
    procedure Close;
    { called on the READER thread: the queue went from empty to not empty, or the end
      was read. The host schedules Pump on the main thread from here. }
    property OnWake: TNotifyEvent read FOnWake write FOnWake;
    { FOR THE TESTS }
    property Outstanding: Int64 read GetOutstanding;           { read, not yet Delivered }
    property MaxOutstanding: Int64 read GetMaxOutstanding;
    property TotalDelivered: Int64 read GetTotalDelivered;
    property WakeCount: Integer read GetWakeCount;
    property Backend: TPtyBackend read FBackend;
    property Started: Boolean read FStarted;
    function ThreadsFinished: Boolean;
  end;

const
  { ms: how long Close waits for the threads, and how often it interrupts meanwhile }
  PtyCloseTimeoutMs = 5000;
  PtyCloseStepMs = 50;

implementation

{ ---- TPtyBackend ------------------------------------------------------------------- }

function TPtyBackend.IsConPty(out ABuild: Integer): Boolean;
begin
  ABuild := 0;
  Result := False;
end;

procedure TPtyBackend.BindReader(AThread: TThread);
begin
end;

{ ---- TPtyThread -------------------------------------------------------------------- }

constructor TPtyThread.Create(ASession: TPtySession; AReader: Boolean);
begin
  FSession := ASession;
  FReader := AReader;
  FreeOnTerminate := False;
  inherited Create(True);
end;

procedure TPtyThread.Execute;
begin
  try
    if FReader then
      FSession.ReadLoop(Self)
    else
      FSession.WriteLoop(Self);
  except
    { a thread must not take the process down; the reader's end is reported below }
  end;
  if FReader then
  begin
    FSession.FLock.Enter;
    try
      if not FSession.FEnded then
      begin
        FSession.FEnded := True;
        FSession.FExitCode := -1;
      end;
    finally
      FSession.FLock.Leave;
    end;
  end;
end;

{ ---- TPtySession ------------------------------------------------------------------- }

constructor TPtySession.Create(ABackend: TPtyBackend; AHigh, ALow, AChunk: Integer);
begin
  inherited Create;
  FBackend := ABackend;
  FHigh := AHigh;
  FLow := ALow;
  FChunk := AChunk;
  if FChunk < 1 then FChunk := 1;
  FLock := TCriticalSection.Create;
  FResume := TEvent.Create(nil, False, False, '');
  FWriteEvent := TEvent.Create(nil, False, False, '');
end;

destructor TPtySession.Destroy;
begin
  try
    Close;
  except
    { a destructor does not raise; Close already said it on its own call }
  end;
  { threads that would not stop are left running with what they use (a leak, not a
    hang: freeing a running TThread waits for it) }
  if ThreadsFinished then
  begin
    FreeAndNil(FReader);
    FreeAndNil(FWriter);
    FreeAndNil(FBackend);
    FreeAndNil(FResume);
    FreeAndNil(FWriteEvent);
    FreeAndNil(FLock);
  end;
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
  if not FBackend.Start(ACommand, ACols, ARows, AError) then
    Exit;
  FStarted := True;
  FReader := TPtyThread.Create(Self, True);
  FWriter := TPtyThread.Create(Self, False);
  FBackend.BindReader(FReader);
  FReader.Start;
  FWriter.Start;
  Result := True;
end;

procedure TPtySession.Wake;
var
  h: TNotifyEvent;
begin
  { not under the lock: the host's callback may take locks of its own }
  InterLockedIncrement(FWakeCount);
  h := FOnWake;
  if Assigned(h) then
    h(Self);
end;

procedure TPtySession.ReadLoop(AThread: TPtyThread);
var
  buf: array of Byte;
  n, code: Integer;
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
      if not discard then
        Wake;
      Exit;
    end;
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

procedure TPtySession.WriteLoop(AThread: TPtyThread);
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

procedure TPtySession.Write(const AData: RawByteString);
begin
  if (AData = '') or not FStarted or FClosed then Exit;
  FLock.Enter;
  try
    FWriteQueue := FWriteQueue + AData;
  finally
    FLock.Leave;
  end;
  FWriteEvent.SetEvent;
end;

procedure TPtySession.Resize(ACols, ARows: Integer);
begin
  if FStarted and not FClosed then
    FBackend.Resize(ACols, ARows);
end;

function TPtySession.Pump(out AData: RawByteString; out AExited: Boolean; out AExitCode: Integer): Boolean;
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

procedure TPtySession.Delivered(ACount: Integer);
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

function TPtySession.ThreadsFinished: Boolean;
begin
  Result := ((FReader = nil) or FReader.Finished) and ((FWriter = nil) or FWriter.Finished);
end;

procedure TPtySession.Close;
var
  waited: Integer;
begin
  if FClosed then Exit;
  FClosed := True;
  if not FStarted then
    Exit;
  { 1. the reader discards and no longer waits for the terminal; the writer stops }
  FLock.Enter;
  try
    FDiscard := True;
    FStopping := True;
    FHeld := False;
  finally
    FLock.Leave;
  end;
  FResume.SetEvent;
  FWriteEvent.SetEvent;
  { 2. interrupt until both are gone -- a cancel that lands between two reads is lost,
    so it is repeated -- bounded }
  FBackend.Interrupt;
  waited := 0;
  while not ThreadsFinished do
  begin
    if waited >= PtyCloseTimeoutMs then
      raise Exception.Create('the PTY threads did not stop within 5 s');
    Sleep(PtyCloseStepMs);
    Inc(waited, PtyCloseStepMs);
    FBackend.Interrupt;
  end;
  FReader.WaitFor;
  FWriter.WaitFor;
  { 3. the handles }
  FBackend.Shutdown;
end;

function TPtySession.GetOutstanding: Int64;
begin
  FLock.Enter;
  try
    Result := FOutstanding;
  finally
    FLock.Leave;
  end;
end;

function TPtySession.GetMaxOutstanding: Int64;
begin
  FLock.Enter;
  try
    Result := FMaxOutstanding;
  finally
    FLock.Leave;
  end;
end;

function TPtySession.GetWakeCount: Integer;
begin
  Result := InterLockedExchangeAdd(FWakeCount, 0);
end;

function TPtySession.GetTotalDelivered: Int64;
begin
  FLock.Enter;
  try
    Result := FTotalDelivered;
  finally
    FLock.Leave;
  end;
end;

end.
