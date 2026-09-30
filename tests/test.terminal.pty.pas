unit test.terminal.pty;
{$mode objfpc}{$H+}
{$modeswitch nestedprocvars}
{ The terminal example's PTY session (examples/terminal/uptysession, ushell): the
  reader and writer threads, one wake-up per batch, back-pressure through the
  terminal's write callbacks, the exit line after the last output, keys and resizes
  to the PTY, the core told about ConPTY, and closing that never hangs.

  A fake backend stands in for the PTY: its Read waits for what the test feeds it (or,
  endless, hands out a full chunk every time), its Interrupt makes a waiting Read
  return. Every wait here is bounded (5 s unless said otherwise) and pumps the message
  loop, so a broken session fails a test instead of hanging the run.

  On Windows, the second part: the pipe backend on real pipes, the build number, and
  ConPTY itself running cmd.exe (no window: a pseudo console has none; the program is
  ended by its handle if it does not go with its console).

  Closing returns at once and finishes on the session's own thread: the tests that
  close wait for the finishers (PtyWaitForFinishers) and count the sessions still
  alive or leaked. A program that will not go with its console is this test runner
  itself, started as a helper (--ty-pty-helper, handled in this unit's initialization
  before any test runs): it blocks in its CTRL_CLOSE_EVENT handler, or leaves its
  console, and sleeps -- only its handle ends it. }

interface

uses
  Classes, SysUtils, SyncObjs, Forms, Controls, LCLType, fpcunit, testregistry,
  tyControls.Terminal.Buffer, tyControls.Terminal.Core, tyControls.Terminal,
  uptysession, ushell, {$IFDEF MSWINDOWS}uptywin,{$ENDIF} test.terminal.view;

type
  { A PTY that is not one. }
  TFakePty = class(TPtyBackend)
  private
    FLock: SyncObjs.TCriticalSection;  { LCLType and Windows have one too }
    FEvent: TEvent;
    FPending: RawByteString;
    FEof: Boolean;
    FEofCode: Int64;
    FInterrupted: Boolean;
    FWritten: RawByteString;
    FResizeCols, FResizeRows, FResizes: Integer;
    FReads: Integer;
    FSent: Int64;
  public
    Endless: Boolean;
    EndlessLimit: Int64;             { 0 = without end }
    MaxRead: Integer;                { > 0: at most this much a read }
    ConPty: Boolean;
    Build: Integer;
    StartResult: Boolean;
    StuckRead: TEvent;               { set: Read waits for it and ignores Interrupt }
    RaiseInRead: Boolean;            { Read raises }
    WriteFails: Boolean;             { Write answers False (the pipe is broken) }
    constructor Create;
    destructor Destroy; override;
    function Start(const ACommand: string; ACols, ARows: Integer; out AError: string): Boolean; override;
    function Read(var ABuf; ACount: Integer): Integer; override;
    function Write(const ABuf; ACount: Integer): Boolean; override;
    procedure Resize(ACols, ARows: Integer); override;
    procedure Interrupt; override;
    function ExitCode(AWaitMs: Integer): Int64; override;
    procedure Shutdown; override;
    function IsConPty(out ABuild: Integer): Boolean; override;
    procedure Feed(const S: RawByteString);
    procedure FeedEof(ACode: Int64);
    function Written: RawByteString;
    function Reads: Integer;
    function LastResize: TPoint;
  end;

  TTyTerminalPtyTests = class(TTestCase)
  private
    F: TTyTermViewFixture;
    FExits: Integer;
    FShellData: RawByteString;
    procedure OnExit(Sender: TObject);
    procedure OnShellData(Sender: TObject; const AData: RawByteString);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestOutputReachesTheTerminal;
    procedure TestOneWakePerBatch;
    procedure TestBackpressureStopsTheReader;
    procedure TestTheExitLineComesLast;
    procedure TestKeysGoToThePty;
    procedure TestResizeFollowsTheGrid;
    procedure TestTheWindowsPtyIsTold;
    procedure TestCloseDoesNotHang;
    procedure TestCloseWhileHeldBack;
    procedure TestBackpressureThroughTheTerminal;
    procedure TestCloseWhileTheProgramExits;
    procedure TestAStuckSessionIsLeftNotFreed;
    procedure TestAReaderThatRaisesEndsTheSession;
    procedure TestNoWritesQueueOnceTheWriterIsGone;
    procedure TestTheExitCodeIsNotAnInteger;
    procedure TestAfterTheExitKeysGoNowhere;
    {$IFDEF MSWINDOWS}
    procedure TestPipesRoundTrip;
    procedure TestInterruptUnblocksARead;
    procedure TestABlockedWriteIsCancelled;
    procedure TestTheBuildNumberIsTheRealOne;
    procedure TestNoConPtyIsReported;
    procedure TestConPtyRunsACommand;
    procedure TestConPtyResizesAndCloses;
    procedure TestConPtyCloseReturnsAtOnceAndEndsAProgramThatStays;
    procedure TestConPtyCloseEndsAProgramThatLeftItsConsole;
    procedure TestConPtyCloseWhileTheProgramExits;
    { phase 7: TProcessPipeBackend }
    procedure TestPipeBackendIsBinarySafe;                   { B1 }
    procedure TestPipeBackendCloseDoesNotWait;               { B2 }
    procedure TestPipeBackendStderr;                         { B3 }
    {$ENDIF}
  end;

{$IFDEF MSWINDOWS}
{ '--ty-pty-helper=block-close' / 'free-console': run as the helper and halt (called
  from the initialization, before any test) }
procedure RunPtyHelperIfAsked;
{$ENDIF}

implementation

{$IFDEF MSWINDOWS}
uses
  Windows, Registry;
{$ENDIF}

type
  TWaitCheck = function: Boolean is nested;

{ ---- TFakePty ---------------------------------------------------------------------- }

constructor TFakePty.Create;
begin
  inherited Create;
  FLock := SyncObjs.TCriticalSection.Create;
  FEvent := SyncObjs.TEvent.Create(nil, False, False, '');
  FEofCode := 0;
  StartResult := True;
end;

destructor TFakePty.Destroy;
begin
  FEvent.Free;
  FLock.Free;
  inherited Destroy;
end;

function TFakePty.Start(const ACommand: string; ACols, ARows: Integer; out AError: string): Boolean;
begin
  AError := '';
  if not StartResult then AError := 'the fake did not start';
  Result := StartResult;
end;

function TFakePty.Read(var ABuf; ACount: Integer): Integer;
var
  n: Integer;
begin
  if RaiseInRead then
    raise Exception.Create('the fake read raises');
  if StuckRead <> nil then
  begin
    StuckRead.WaitFor(INFINITE);
    Exit(0);
  end;
  while True do
  begin
    FLock.Enter;
    try
      if FInterrupted then Exit(0);
      if Endless then
      begin
        if (EndlessLimit > 0) and (FSent >= EndlessLimit) then Exit(0);
        n := ACount;
        if (EndlessLimit > 0) and (FSent + n > EndlessLimit) then n := EndlessLimit - FSent;
        FillChar(ABuf, n, Ord('x'));
        Inc(FSent, n);
        Inc(FReads);
        Exit(n);
      end;
      if FPending <> '' then
      begin
        n := Length(FPending);
        if n > ACount then n := ACount;
        if (MaxRead > 0) and (n > MaxRead) then n := MaxRead;
        Move(FPending[1], ABuf, n);
        Delete(FPending, 1, n);
        Inc(FReads);
        Exit(n);
      end;
      if FEof then Exit(0);
    finally
      FLock.Leave;
    end;
    FEvent.WaitFor(20);
  end;
end;

function TFakePty.Write(const ABuf; ACount: Integer): Boolean;
var
  s: RawByteString;
begin
  SetLength(s, ACount);
  if ACount > 0 then Move(ABuf, s[1], ACount);
  FLock.Enter;
  try
    FWritten := FWritten + s;
    Result := not FInterrupted and not WriteFails;
  finally
    FLock.Leave;
  end;
end;

procedure TFakePty.Resize(ACols, ARows: Integer);
begin
  FLock.Enter;
  try
    FResizeCols := ACols;
    FResizeRows := ARows;
    Inc(FResizes);
  finally
    FLock.Leave;
  end;
end;

procedure TFakePty.Interrupt;
begin
  FLock.Enter;
  try
    FInterrupted := True;
  finally
    FLock.Leave;
  end;
  FEvent.SetEvent;
end;

function TFakePty.ExitCode(AWaitMs: Integer): Int64;
begin
  FLock.Enter;
  try
    Result := FEofCode;
  finally
    FLock.Leave;
  end;
end;

procedure TFakePty.Shutdown;
begin
end;

function TFakePty.IsConPty(out ABuild: Integer): Boolean;
begin
  ABuild := Build;
  Result := ConPty;
end;

procedure TFakePty.Feed(const S: RawByteString);
begin
  FLock.Enter;
  try
    FPending := FPending + S;
  finally
    FLock.Leave;
  end;
  FEvent.SetEvent;
end;

procedure TFakePty.FeedEof(ACode: Int64);
begin
  FLock.Enter;
  try
    FEof := True;
    FEofCode := ACode;
  finally
    FLock.Leave;
  end;
  FEvent.SetEvent;
end;

function TFakePty.Written: RawByteString;
begin
  FLock.Enter;
  try
    Result := FWritten;
  finally
    FLock.Leave;
  end;
end;

function TFakePty.Reads: Integer;
begin
  FLock.Enter;
  try
    Result := FReads;
  finally
    FLock.Leave;
  end;
end;

function TFakePty.LastResize: TPoint;
begin
  FLock.Enter;
  try
    Result := Classes.Point(FResizeCols, FResizeRows);
  finally
    FLock.Leave;
  end;
end;

{ ---- the tests ---------------------------------------------------------------------- }

procedure TTyTerminalPtyTests.SetUp;
begin
  F := TTyTermViewFixture.Create;
  F.SizeTo(40, 6);
  { real slices through the message loop (the shell's pump is a QueueAsyncCall too) }
  F.View.PassSlices := True;
  FExits := 0;
  FShellData := '';
end;

procedure TTyTerminalPtyTests.TearDown;
begin
  Application.ProcessMessages;
  FreeAndNil(F);
  { a test that failed half way leaves its session finishing: not into the next test }
  PtyWaitForFinishers(PtyExitWaitMs);
end;

procedure TTyTerminalPtyTests.OnExit(Sender: TObject);
begin
  Inc(FExits);
end;

procedure TTyTerminalPtyTests.OnShellData(Sender: TObject; const AData: RawByteString);
begin
  FShellData := FShellData + AData;
end;

{ bounded waiting with the message loop turning }
function WaitUntil(ACheck: TWaitCheck; AMs: Integer = 5000): Boolean;
var
  t0: QWord;
begin
  t0 := GetTickCount64;
  repeat
    Application.ProcessMessages;
    if ACheck() then Exit(True);
    Sleep(5);
  until GetTickCount64 - t0 > QWord(AMs);
  Application.ProcessMessages;
  Result := ACheck();
end;

procedure TTyTerminalPtyTests.TestOutputReachesTheTerminal;
var
  fake: TFakePty;
  sh: TTerminalShell;
  err: string;

  function Done: Boolean;
  begin
    Result := F.RowText(0) = 'hello';
  end;

begin
  fake := TFakePty.Create;
  sh := TTerminalShell.Create(F.View, fake);
  try
    AssertTrue('started', sh.Start('fake', err));
    fake.Feed('hello');
    AssertTrue('the output reached the terminal: ' + F.RowText(0), WaitUntil(@Done));
  finally
    sh.Free;
  end;
end;

procedure TTyTerminalPtyTests.TestOneWakePerBatch;
var
  fake: TFakePty;
  s: TPtySession;
  err: string;
  i: Integer;
  data: RawByteString;
  exited: Boolean;
  code: Int64;

  function AllRead: Boolean;
  begin
    Result := s.Outstanding = 100 * 10;
  end;

  function OneMore: Boolean;
  begin
    Result := s.Outstanding = 100 * 10 + 10;
  end;

begin
  fake := TFakePty.Create;
  s := TPtySession.Create(fake);
  try
    { ten bytes a read: a hundred reads, whatever the threads' timing }
    fake.MaxRead := 10;
    AssertTrue('started', s.Start('fake', 80, 24, err));
    for i := 1 to 100 do
      fake.Feed('0123456789');
    AssertTrue('all read', WaitUntil(@AllRead));
    AssertEquals('one wake while nobody pumps', 1, s.WakeCount);
    AssertTrue('something to pump', s.Pump(data, exited, code));
    AssertEquals('everything in one pump', 1000, Length(data));
    AssertTrue('the pump leaves the count to Delivered', AllRead);
    fake.Feed('0123456789');
    AssertTrue('one more read', WaitUntil(@OneMore));
    AssertEquals('the next batch wakes again', 2, s.WakeCount);
  finally
    s.Free;
  end;
end;

procedure TTyTerminalPtyTests.TestBackpressureStopsTheReader;
var
  fake: TFakePty;
  s: TPtySession;
  err: string;
  data: RawByteString;
  exited: Boolean;
  code: Int64;
  before: Integer;

  function Grew: Boolean;
  begin
    Result := fake.Reads > before;
  end;

begin
  fake := TFakePty.Create;
  fake.Endless := True;
  s := TPtySession.Create(fake, 64 * 1024, 16 * 1024, 8 * 1024);
  try
    AssertTrue('started', s.Start('fake', 80, 24, err));
    Sleep(1000);
    AssertTrue(Format('held at the high water mark plus a chunk (%d)', [s.MaxOutstanding]),
      s.MaxOutstanding <= 64 * 1024 + 8 * 1024);
    AssertTrue('it did read up to it', s.MaxOutstanding > 64 * 1024 - 8 * 1024);
    before := fake.Reads;
    s.Pump(data, exited, code);
    s.Delivered(Length(data));
    AssertTrue('below the low mark it reads again', WaitUntil(@Grew, 200));
  finally
    s.Free;
  end;
end;

procedure TTyTerminalPtyTests.TestTheExitLineComesLast;
var
  fake: TFakePty;
  sh: TTerminalShell;
  err: string;

  function Exited: Boolean;
  begin
    Result := FExits > 0;
  end;

begin
  fake := TFakePty.Create;
  sh := TTerminalShell.Create(F.View, fake);
  try
    sh.OnExit := @OnExit;
    AssertTrue('started', sh.Start('fake', err));
    fake.Feed('a'#13#10'b');
    fake.FeedEof(3);
    AssertTrue('the exit was announced', WaitUntil(@Exited));
    AssertEquals('once', 1, FExits);
    AssertEquals('the code', 3, sh.ExitCode);
    AssertFalse('not running', sh.Running);
    AssertEquals('a', F.RowText(0));
    AssertEquals('b', F.RowText(1));
    AssertEquals('then the line', Format(rsShellExited, [3]), F.RowText(2));
  finally
    sh.Free;
  end;
end;

procedure TTyTerminalPtyTests.TestKeysGoToThePty;
var
  fake: TFakePty;
  sh: TTerminalShell;
  err: string;
  ch: TUTF8Char;

  function Arrived: Boolean;
  begin
    Result := fake.Written = 'x';
  end;

begin
  fake := TFakePty.Create;
  sh := TTerminalShell.Create(F.View, fake);
  try
    sh.OnData := @OnShellData;
    AssertTrue('started', sh.Start('fake', err));
    ch := 'x';
    F.View.TypeChar(ch);
    AssertTrue('the key reached the PTY', WaitUntil(@Arrived, 2000));
    AssertEquals('and the host still sees it', 'x', FShellData);
  finally
    sh.Free;
  end;
end;

procedure TTyTerminalPtyTests.TestResizeFollowsTheGrid;
var
  fake: TFakePty;
  sh: TTerminalShell;
  err: string;
begin
  fake := TFakePty.Create;
  sh := TTerminalShell.Create(F.View, fake);
  try
    AssertTrue('started', sh.Start('fake', err));
    F.SizeTo(100, 30);
    AssertEquals('100 columns', 100, F.View.Cols);
    AssertEquals('the PTY got the columns', F.View.Cols, fake.LastResize.X);
    AssertEquals('and the rows', F.View.Rows, fake.LastResize.Y);
    AssertEquals(30, fake.LastResize.Y);
    AssertTrue('the host still hears about it', Length(F.Grids) > 0);
  finally
    sh.Free;
  end;
end;

procedure TTyTerminalPtyTests.TestTheWindowsPtyIsTold;
var
  fake: TFakePty;
  sh: TTerminalShell;
  err: string;
begin
  fake := TFakePty.Create;
  fake.ConPty := True;
  fake.Build := 19044;
  sh := TTerminalShell.Create(F.View, fake);
  try
    AssertTrue('started', sh.Start('fake', err));
    AssertTrue('ConPTY', F.View.Core.WindowsPty.Backend = twpConPty);
    AssertEquals('its build', 19044, F.View.Core.WindowsPty.BuildNumber);
  finally
    sh.Free;
  end;
  fake := TFakePty.Create;
  sh := TTerminalShell.Create(F.View, fake);
  try
    AssertTrue('started', sh.Start('fake', err));
    AssertTrue('no ConPTY', F.View.Core.WindowsPty.Backend = twpNone);
    AssertEquals('no build', 0, F.View.Core.WindowsPty.BuildNumber);
  finally
    sh.Free;
  end;
end;

{ closing is two steps: Close returns at once, the finisher stops the threads and frees
  the session behind it; both counted }
procedure TTyTerminalPtyTests.TestCloseDoesNotHang;
var
  fake: TFakePty;
  s: TPtySession;
  sh: TTerminalShell;
  err: string;
  t0: QWord;
  alive, pumps: Integer;
begin
  AssertTrue('nothing finishing from before', PtyWaitForFinishers(PtyExitWaitMs));
  alive := PtySessionsAlive;
  fake := TFakePty.Create;
  s := TPtySession.Create(fake);
  try
    AssertTrue('started', s.Start('fake', 80, 24, err));
    AssertEquals('one session alive', alive + 1, PtySessionsAlive);
    Sleep(50);                                 { the reader is waiting in Read }
    t0 := GetTickCount64;
    s.Close;
    AssertTrue(Format('Close returned at once (%d ms)', [GetTickCount64 - t0]), GetTickCount64 - t0 < 200);
    s.Close;                                   { again: nothing }
  finally
    s.Free;
  end;
  AssertTrue('the finisher finished', PtyWaitForFinishers(2000));
  AssertEquals('and freed the session', alive, PtySessionsAlive);
  { a shell freed with a pump still queued: the pump is taken out, not run on the freed
    shell (PumpsRun is a class variable -- it counts a pump on freed memory too) }
  fake := TFakePty.Create;
  sh := TTerminalShell.Create(F.View, fake);
  AssertTrue('started', sh.Start('fake', err));
  fake.Feed('queued');
  Sleep(100);                                  { the wake is queued, not run }
  pumps := TTerminalShell.PumpsRun;
  t0 := GetTickCount64;
  sh.Free;
  AssertTrue(Format('the shell went at once (%d ms)', [GetTickCount64 - t0]), GetTickCount64 - t0 < 200);
  Application.ProcessMessages;                 { would run the freed shell's pump }
  Application.ProcessMessages;
  AssertEquals('no pump ran after the shell was freed', pumps, TTerminalShell.PumpsRun);
  AssertTrue('its session finished', PtyWaitForFinishers(2000));
  AssertEquals('and was freed', alive, PtySessionsAlive);
end;

procedure TTyTerminalPtyTests.TestCloseWhileHeldBack;
var
  fake: TFakePty;
  s: TPtySession;
  err: string;
  t0: QWord;

  function Held: Boolean;
  begin
    Result := s.MaxOutstanding >= 16 * 1024;
  end;

begin
  fake := TFakePty.Create;
  fake.Endless := True;
  s := TPtySession.Create(fake, 16 * 1024, 4 * 1024, 4 * 1024);
  try
    AssertTrue('started', s.Start('fake', 80, 24, err));
    AssertTrue('held back', WaitUntil(@Held));
    Sleep(100);
    t0 := GetTickCount64;
    s.Close;
    AssertTrue(Format('Close returned at once (%d ms)', [GetTickCount64 - t0]), GetTickCount64 - t0 < 200);
  finally
    s.Free;
  end;
  { the reader, held back, is let go: within a second, not after the finisher's bound }
  t0 := GetTickCount64;
  AssertTrue('the finisher finished', PtyWaitForFinishers(PtyExitWaitMs));
  AssertTrue(Format('within a second (%d ms)', [GetTickCount64 - t0]), GetTickCount64 - t0 < 1000);
end;

procedure TTyTerminalPtyTests.TestBackpressureThroughTheTerminal;
const
  Total = 5 * 1024 * 1024;
var
  fake: TFakePty;
  sh: TTerminalShell;
  err: string;

  function Exited: Boolean;
  begin
    Result := FExits > 0;
  end;

begin
  fake := TFakePty.Create;
  fake.Endless := True;
  fake.EndlessLimit := Total;
  sh := TTerminalShell.Create(F.View, fake, 256 * 1024, 64 * 1024);
  try
    sh.OnExit := @OnExit;
    AssertTrue('started', sh.Start('fake', err));
    AssertTrue('all of it through the terminal to the end', WaitUntil(@Exited, 120000));
    AssertEquals('every byte parsed and counted back', Int64(Total), sh.Session.TotalDelivered);
    AssertTrue(Format('never more than the high mark plus a chunk ahead (%d)', [sh.Session.MaxOutstanding]),
      sh.Session.MaxOutstanding <= 256 * 1024 + 65536);
  finally
    sh.Free;
  end;
end;

{ the program's end and the user's close at the same moment, many times over: nothing
  of a freed shell runs (no pump, no exit line), every session is finished and freed }
procedure TTyTerminalPtyTests.TestCloseWhileTheProgramExits;
var
  fake: TFakePty;
  sh: TTerminalShell;
  err: string;
  alive, pumps, exits, i: Integer;
begin
  AssertTrue('nothing finishing from before', PtyWaitForFinishers(PtyExitWaitMs));
  alive := PtySessionsAlive;
  for i := 0 to 29 do
  begin
    fake := TFakePty.Create;
    sh := TTerminalShell.Create(F.View, fake);
    sh.OnExit := @OnExit;
    AssertTrue('started', sh.Start('fake', err));
    fake.Feed('bye');
    fake.FeedEof(i);
    { 0..2 ms: before the reader read the end, while it wakes, after the pump is queued }
    if i mod 3 > 0 then Sleep(i mod 3);
    if i mod 5 = 4 then Application.ProcessMessages;
    exits := FExits;
    pumps := TTerminalShell.PumpsRun;
    sh.Free;
    Application.ProcessMessages;
    Application.ProcessMessages;
    AssertEquals(Format('round %d: no pump after the free', [i]), pumps, TTerminalShell.PumpsRun);
    AssertEquals(Format('round %d: no exit line after the free', [i]), exits, FExits);
  end;
  AssertTrue('every finisher finished', PtyWaitForFinishers(PtyExitWaitMs));
  AssertEquals('every session was freed', alive, PtySessionsAlive);
end;

{ a reader that will not come out of Read: Close still returns at once, and the
  finisher leaves the session (its threads use it) instead of freeing it }
procedure TTyTerminalPtyTests.TestAStuckSessionIsLeftNotFreed;
var
  fake: TFakePty;
  s: TPtySession;
  stuck: TEvent;
  err: string;
  t0: QWord;
  alive, leaked: Integer;
begin
  AssertTrue('nothing finishing from before', PtyWaitForFinishers(PtyExitWaitMs));
  alive := PtySessionsAlive;
  leaked := PtySessionsLeaked;
  stuck := TEvent.Create(nil, True, False, '');
  fake := TFakePty.Create;
  fake.StuckRead := stuck;
  s := TPtySession.Create(fake);
  AssertTrue('started', s.Start('fake', 80, 24, err));
  Sleep(50);
  t0 := GetTickCount64;
  s.Free;
  AssertTrue(Format('Close returned at once (%d ms)', [GetTickCount64 - t0]), GetTickCount64 - t0 < 200);
  AssertTrue('the finisher gave up within its bound', PtyWaitForFinishers(PtyExitWaitMs));
  AssertEquals('one session left behind', leaked + 1, PtySessionsLeaked);
  AssertEquals('and not freed', alive + 1, PtySessionsAlive);
  { let the reader go: it ends in the session that was left for it (never freed) }
  stuck.SetEvent;
  Sleep(100);
  { the event stays: the leaked fake still points at it }
end;

{ an exception in the reader is an end like any other: the host shows the exit line }
procedure TTyTerminalPtyTests.TestAReaderThatRaisesEndsTheSession;
var
  fake: TFakePty;
  sh: TTerminalShell;
  err: string;

  function Exited: Boolean;
  begin
    Result := FExits > 0;
  end;

begin
  fake := TFakePty.Create;
  fake.RaiseInRead := True;
  sh := TTerminalShell.Create(F.View, fake);
  try
    sh.OnExit := @OnExit;
    AssertTrue('started', sh.Start('fake', err));
    AssertTrue('the exit was announced', WaitUntil(@Exited));
    AssertEquals('code not known', Int64(-1), sh.ExitCode);
    AssertEquals('the line', Format(rsShellExited, [-1]), F.RowText(1));
  finally
    sh.Free;
  end;
end;

procedure TTyTerminalPtyTests.TestNoWritesQueueOnceTheWriterIsGone;
var
  fake: TFakePty;
  s: TPtySession;
  err: string;

  function Gone: Boolean;
  begin
    Result := s.WriterGone;
  end;

begin
  fake := TFakePty.Create;
  fake.WriteFails := True;
  s := TPtySession.Create(fake);
  try
    AssertTrue('started', s.Start('fake', 80, 24, err));
    s.Write('a');
    AssertTrue('the broken write ended the writer', WaitUntil(@Gone));
    s.Write('bbbb');
    AssertEquals('nothing queues up behind it', 0, s.PendingWrite);
  finally
    s.Free;
  end;
end;

{ Windows exit codes are DWORDs: 4294967295 is a code, not "not known" }
procedure TTyTerminalPtyTests.TestTheExitCodeIsNotAnInteger;
const
  Big = Int64(4294967295);
var
  fake: TFakePty;
  sh: TTerminalShell;
  err: string;

  function Exited: Boolean;
  begin
    Result := FExits > 0;
  end;

begin
  fake := TFakePty.Create;
  sh := TTerminalShell.Create(F.View, fake);
  try
    sh.OnExit := @OnExit;
    AssertTrue('started', sh.Start('fake', err));
    fake.FeedEof(Big);
    AssertTrue('the exit was announced', WaitUntil(@Exited));
    AssertEquals('the code', Big, sh.ExitCode);
    AssertEquals('the line', Format(rsShellExited, [Big]), F.RowText(1));
  finally
    sh.Free;
  end;
end;

procedure TTyTerminalPtyTests.TestAfterTheExitKeysGoNowhere;
var
  fake: TFakePty;
  sh: TTerminalShell;
  err: string;
  ch: TUTF8Char;

  function Exited: Boolean;
  begin
    Result := FExits > 0;
  end;

begin
  fake := TFakePty.Create;
  sh := TTerminalShell.Create(F.View, fake);
  try
    sh.OnExit := @OnExit;
    AssertTrue('started', sh.Start('fake', err));
    AssertFalse('writable while it runs', F.View.ReadOnly);
    fake.FeedEof(0);
    AssertTrue('the exit was announced', WaitUntil(@Exited));
    AssertTrue('read-only again', F.View.ReadOnly);
    ch := 'x';
    F.View.TypeChar(ch);
    { a host that turns read-only off again: the shell itself drops the keys }
    F.View.ReadOnly := False;
    ch := 'y';
    F.View.TypeChar(ch);
    Sleep(200);
    AssertEquals('no key reached the PTY', '', fake.Written);
    AssertEquals('none was queued', 0, sh.Session.PendingWrite);
  finally
    sh.Free;
  end;
end;

{$IFDEF MSWINDOWS}

{ ---- Windows: pipes, the build, ConPTY -------------------------------------------- }

{ ESC [ ... final and ESC ] ... BEL / ST taken out: what ConPTY paints around the text }
function StripEscapes(const S: RawByteString): RawByteString;
var
  i: Integer;
begin
  Result := '';
  i := 1;
  while i <= Length(S) do
  begin
    if (S[i] = #27) and (i < Length(S)) and (S[i + 1] = '[') then
    begin
      Inc(i, 2);
      while (i <= Length(S)) and not (S[i] in [#$40..#$7E]) do Inc(i);
      Inc(i);
    end
    else if (S[i] = #27) and (i < Length(S)) and (S[i + 1] = ']') then
    begin
      Inc(i, 2);
      while (i <= Length(S)) and (S[i] <> #7) and (S[i] <> #27) do Inc(i);
      if (i <= Length(S)) and (S[i] = #27) then Inc(i);
      Inc(i);
    end
    else if S[i] = #27 then
      Inc(i, 2)
    else
    begin
      Result := Result + S[i];
      Inc(i);
    end;
  end;
end;

procedure TTyTerminalPtyTests.TestPipesRoundTrip;
var
  inRead, inWrite, outRead, outWrite: THandle;
  s: TPtySession;
  err: string;
  data, all: RawByteString;
  exited, ended: Boolean;
  code: Int64;
  buf: array[0..15] of AnsiChar;
  got, avail, written: DWORD;

  function Three: Boolean;
  begin
    Result := s.Outstanding = 3;
  end;

  function Arrived: Boolean;
  begin
    avail := 0;
    Result := PeekNamedPipe(inRead, nil, 0, nil, @avail, nil) and (avail >= 3);
  end;

  function TheEnd: Boolean;
  begin
    if s.Pump(data, exited, code) and exited then ended := True;
    Result := ended;
  end;

begin
  AssertTrue('pipes', CreatePipe(inRead, inWrite, nil, 0) and CreatePipe(outRead, outWrite, nil, 0));
  s := TPtySession.Create(TPipeBackend.Create(inWrite, outRead, True));
  try
    AssertTrue('started', s.Start('', 80, 24, err));
    all := 'abc';
    written := 0;
    AssertTrue(WriteFile(outWrite, all[1], 3, written, nil));
    AssertTrue('read by the session', WaitUntil(@Three));
    AssertTrue(s.Pump(data, exited, code));
    AssertEquals('abc', data);
    s.Write('xyz');
    AssertTrue('written by the session', WaitUntil(@Arrived));
    got := 0;
    AssertTrue(ReadFile(inRead, buf, 3, got, nil));
    AssertEquals('xyz', Copy(buf, 1, got));
    { the program's end closes its side: the reader reads the end }
    CloseHandle(outWrite);
    outWrite := 0;
    ended := False;
    AssertTrue('the end is reported', WaitUntil(@TheEnd));
  finally
    s.Free;
    if outWrite <> 0 then CloseHandle(outWrite);
    CloseHandle(inRead);
  end;
end;

procedure TTyTerminalPtyTests.TestInterruptUnblocksARead;
var
  inRead, inWrite, outRead, outWrite: THandle;
  s: TPtySession;
  err: string;
  t0: QWord;
begin
  AssertTrue('pipes', CreatePipe(inRead, inWrite, nil, 0) and CreatePipe(outRead, outWrite, nil, 0));
  s := TPtySession.Create(TPipeBackend.Create(inWrite, outRead, True));
  try
    AssertTrue('started', s.Start('', 80, 24, err));
    Sleep(100);                                  { the reader blocks in ReadFile }
    t0 := GetTickCount64;
    s.Close;
    AssertTrue(Format('Close returned at once (%d ms)', [GetTickCount64 - t0]), GetTickCount64 - t0 < 200);
    { our ends of the pipes stay open: only the cancel gets the reader out }
    AssertTrue('the blocked read was cancelled within a second', PtyWaitForFinishers(1000));
  finally
    s.Free;
    CloseHandle(outWrite);
    CloseHandle(inRead);
  end;
end;

{ the program reads no input: the writer blocks in WriteFile on a full pipe; closing
  cancels it (a writer that could not be got out would leave the session behind) }
procedure TTyTerminalPtyTests.TestABlockedWriteIsCancelled;
var
  inRead, inWrite, outRead, outWrite: THandle;
  s: TPtySession;
  err: string;
  t0: QWord;
  alive, leaked: Integer;
  big: RawByteString;
begin
  AssertTrue('nothing finishing from before', PtyWaitForFinishers(PtyExitWaitMs));
  alive := PtySessionsAlive;
  leaked := PtySessionsLeaked;
  AssertTrue('pipes', CreatePipe(inRead, inWrite, nil, 4096) and CreatePipe(outRead, outWrite, nil, 0));
  s := TPtySession.Create(TPipeBackend.Create(inWrite, outRead, True));
  try
    AssertTrue('started', s.Start('', 80, 24, err));
    SetLength(big, 1024 * 1024);
    FillChar(big[1], Length(big), Ord('k'));
    s.Write(big);
    Sleep(200);                                  { the writer blocks in WriteFile }
    AssertEquals('the writer took it (and is blocked with it)', 0, s.PendingWrite);
    t0 := GetTickCount64;
    s.Close;
    AssertTrue(Format('Close returned at once (%d ms)', [GetTickCount64 - t0]), GetTickCount64 - t0 < 200);
    AssertTrue('the blocked write was cancelled within a second', PtyWaitForFinishers(1000));
    AssertEquals('nothing left behind', leaked, PtySessionsLeaked);
    AssertEquals('the session was freed', alive, PtySessionsAlive);
  finally
    s.Free;
    CloseHandle(outWrite);
    CloseHandle(inRead);
  end;
end;

procedure TTyTerminalPtyTests.TestTheBuildNumberIsTheRealOne;
var
  reg: TRegistry;
  want: Integer;
begin
  reg := TRegistry.Create(KEY_READ);
  try
    reg.RootKey := HKEY_LOCAL_MACHINE;
    AssertTrue('the key', reg.OpenKeyReadOnly('SOFTWARE\Microsoft\Windows NT\CurrentVersion'));
    want := StrToInt(reg.ReadString('CurrentBuildNumber'));
  finally
    reg.Free;
  end;
  AssertEquals('RtlGetVersion''s build is the registry''s', want, TyWindowsBuildNumber);
  AssertTrue('Windows 10 or later', TyWindowsBuildNumber >= 10240);
end;

function NoConPty: Boolean;
begin
  Result := False;
end;

procedure TTyTerminalPtyTests.TestNoConPtyIsReported;
var
  s: TPtySession;
  err: string;
begin
  TConPtyBackend.ConPtyLoader := @NoConPty;
  try
    s := TPtySession.Create(TConPtyBackend.Create);
    try
      AssertFalse('not started', s.Start('cmd.exe', 80, 24, err));
      AssertEquals('said why', rsConPtyUnavailable, err);
      AssertFalse('no threads', s.Started);
    finally
      s.Free;
    end;
  finally
    TConPtyBackend.ConPtyLoader := nil;
  end;
end;

procedure TTyTerminalPtyTests.TestConPtyRunsACommand;
var
  s: TPtySession;
  err: string;
  all, data: RawByteString;
  exited, ended: Boolean;
  code, endCode: Int64;

  function TheEnd: Boolean;
  begin
    if s.Pump(data, exited, code) then
    begin
      all := all + data;
      s.Delivered(Length(data));
      if exited then
      begin
        ended := True;
        endCode := code;
      end;
    end;
    Result := ended;
  end;

begin
  if not TyConPtyAvailable then
    Ignore('this Windows has no ConPTY (1809 or later is needed)');
  s := TPtySession.Create(TConPtyBackend.Create);
  try
    if not s.Start('cmd.exe /d /c echo tyterm-ok& exit 7', 80, 24, err) then Fail('not started: ' + err);
    all := '';
    ended := False;
    endCode := -2;
    AssertTrue('the program ended within 10 s', WaitUntil(@TheEnd, 10000));
    AssertTrue('its output came through: ' + StripEscapes(all), Pos('tyterm-ok', StripEscapes(all)) > 0);
    AssertEquals('its exit code', Int64(7), endCode);
  finally
    s.Free;
  end;
end;

procedure TTyTerminalPtyTests.TestConPtyResizesAndCloses;
var
  s: TPtySession;
  b: TConPtyBackend;
  err: string;
  proc: THandle;
  t0: QWord;
begin
  if not TyConPtyAvailable then
    Ignore('this Windows has no ConPTY (1809 or later is needed)');
  b := TConPtyBackend.Create;
  s := TPtySession.Create(b);
  proc := 0;
  try
    if not s.Start('cmd.exe /d /k', 80, 24, err) then Fail('not started: ' + err);
    proc := OpenProcess(SYNCHRONIZE, False, b.ProcessId);
    AssertTrue('the program is there', proc <> 0);
    s.Resize(100, 40);
    AssertEquals('ResizePseudoConsole succeeded', 0, b.LastResizeResult);
    t0 := GetTickCount64;
    s.Close;
    AssertTrue(Format('Close returned at once (%d ms)', [GetTickCount64 - t0]), GetTickCount64 - t0 < 200);
    AssertEquals('the program went with its console', WAIT_OBJECT_0, WaitForSingleObject(proc, PtyExitWaitMs));
    AssertTrue('the finisher finished', PtyWaitForFinishers(PtyExitWaitMs));
  finally
    s.Free;
    if proc <> 0 then CloseHandle(proc);
  end;
end;

{ ---- the helper: this runner, started under a pseudo console ---------------------- }

function HelperBlockClose(ACtrl: DWORD): WINBOOL; stdcall;
begin
  { the close, the log-off, the shut-down: never done -- only its handle ends it }
  if (ACtrl = CTRL_CLOSE_EVENT) or (ACtrl = CTRL_LOGOFF_EVENT) or (ACtrl = CTRL_SHUTDOWN_EVENT) then
    Sleep(INFINITE);
  Result := True;
end;

procedure HelperSay(const S: RawByteString);
var
  h: THandle;
  done: DWORD;
begin
  { the console's own output (the standard handles may be the runner's redirection) }
  h := CreateFileW('CONOUT$', GENERIC_READ or GENERIC_WRITE, FILE_SHARE_READ or FILE_SHARE_WRITE, nil,
    OPEN_EXISTING, 0, 0);
  if h = INVALID_HANDLE_VALUE then Exit;
  done := 0;
  WriteFile(h, S[1], Length(S), done, nil);
  CloseHandle(h);
end;

{ phase 7, the pipe backend: on the standard handles themselves (pipes there) }
procedure HelperOnPipes(const AMode: string);
var
  i: Integer;
  buf: array[0..4095] of Byte;
  got, done: DWORD;
  s: RawByteString;
begin
  if AMode = 'dump' then
  begin
    { every byte value, four times }
    SetLength(s, 1024);
    for i := 0 to 1023 do
      s[i + 1] := AnsiChar(i and 255);
    done := 0;
    { under a pseudo console (the tests' control group) there is no standard handle:
      the console's own output }
    if not WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), s[1], Length(s), done, nil) then
      HelperSay(s);
    Sleep(500);                          { a pseudo console renders only while we are here }
  end
  else if AMode = 'cat' then
  begin
    { what comes in goes out, until the input ends }
    while ReadFile(GetStdHandle(STD_INPUT_HANDLE), buf[0], SizeOf(buf), got, nil) and (got > 0) do
      WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), buf[0], got, done, nil);
  end
  else if AMode = 'stderr' then
  begin
    s := 'ty-out';
    WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), s[1], Length(s), done, nil);
    s := 'ty-err';
    WriteFile(GetStdHandle(STD_ERROR_HANDLE), s[1], Length(s), done, nil);
  end
  else
    Sleep(60000);                        { 'sleep': a program that does not go }
  Halt(0);
end;

procedure RunPtyHelperIfAsked;
const
  Flag = '--ty-pty-helper=';
var
  mode: string;
begin
  if Copy(ParamStr(1), 1, Length(Flag)) <> Flag then Exit;
  mode := Copy(ParamStr(1), Length(Flag) + 1, MaxInt);
  if (mode = 'dump') or (mode = 'cat') or (mode = 'stderr') or (mode = 'sleep') then
    HelperOnPipes(mode);
  if mode = 'block-close' then
    SetConsoleCtrlHandler(@HelperBlockClose, True);
  HelperSay('ty-helper-ready'#13#10);
  if mode = 'free-console' then
    FreeConsole;
  Sleep(60000);
  Halt(0);
end;

{ the helper's run: Close returns at once, the program is ended by its handle (exit code
  1 is TerminateProcess's; a program that went on its own would have another), nothing
  is left behind -- looked up by the helper's PID only }
procedure CloseAHelper(ACase: TTestCase; const AMode: string);
var
  s: TPtySession;
  b: TConPtyBackend;
  err: string;
  all, data: RawByteString;
  exited: Boolean;
  code: Int64;
  proc: THandle;
  t0: QWord;
  alive, leaked: Integer;
  exitCode: DWORD;

  function Ready: Boolean;
  begin
    if s.Pump(data, exited, code) then
    begin
      all := all + data;
      s.Delivered(Length(data));
    end;
    Result := Pos('ty-helper-ready', StripEscapes(all)) > 0;
  end;

begin
  ACase.AssertTrue('nothing finishing from before', PtyWaitForFinishers(PtyExitWaitMs));
  alive := PtySessionsAlive;
  leaked := PtySessionsLeaked;
  b := TConPtyBackend.Create;
  s := TPtySession.Create(b);
  proc := 0;
  try
    if not s.Start('"' + ParamStr(0) + '" --ty-pty-helper=' + AMode, 80, 24, err) then ACase.Fail('not started: ' + err);
    proc := OpenProcess(SYNCHRONIZE or PROCESS_QUERY_LIMITED_INFORMATION, False, b.ProcessId);
    ACase.AssertTrue('the helper is there', proc <> 0);
    all := '';
    ACase.AssertTrue('the helper is ready: ' + StripEscapes(all), WaitUntil(@Ready, 20000));
    t0 := GetTickCount64;
    s.Close;
    ACase.AssertTrue(Format('Close returned at once (%d ms)', [GetTickCount64 - t0]), GetTickCount64 - t0 < 200);
    ACase.AssertEquals('the helper is gone', WAIT_OBJECT_0, WaitForSingleObject(proc, PtyExitWaitMs));
    exitCode := 0;
    ACase.AssertTrue(GetExitCodeProcess(proc, exitCode));
    ACase.AssertEquals('ended by its handle', Int64(1), Int64(exitCode));
    ACase.AssertTrue('the finisher finished', PtyWaitForFinishers(PtyExitWaitMs));
    ACase.AssertEquals('nothing left behind', leaked, PtySessionsLeaked);
    ACase.AssertEquals('the session was freed', alive, PtySessionsAlive);
  finally
    s.Free;
    if proc <> 0 then
    begin
      { a failed run must not leave the helper for a minute: by its handle }
      if WaitForSingleObject(proc, 0) <> WAIT_OBJECT_0 then
      begin
        CloseHandle(proc);
        proc := OpenProcess(PROCESS_TERMINATE, False, b.ProcessId);
        if proc <> 0 then TerminateProcess(proc, 2);
      end;
      if proc <> 0 then CloseHandle(proc);
    end;
  end;
end;

{ the helper sits in its CTRL_CLOSE_EVENT handler: ClosePseudoConsole (before 24H2)
  would wait for it; the finisher ends it by its handle after PtyCloseWaitMs }
procedure TTyTerminalPtyTests.TestConPtyCloseReturnsAtOnceAndEndsAProgramThatStays;
begin
  if not TyConPtyAvailable then
    Ignore('this Windows has no ConPTY (1809 or later is needed)');
  CloseAHelper(Self, 'block-close');
end;

{ the helper left its console: ClosePseudoConsole returns, the program stays }
procedure TTyTerminalPtyTests.TestConPtyCloseEndsAProgramThatLeftItsConsole;
begin
  if not TyConPtyAvailable then
    Ignore('this Windows has no ConPTY (1809 or later is needed)');
  CloseAHelper(Self, 'free-console');
end;

{ the program's end and the user's close together, on a real pseudo console }
procedure TTyTerminalPtyTests.TestConPtyCloseWhileTheProgramExits;
var
  s: TPtySession;
  b: TConPtyBackend;
  err: string;
  procs: array[0..4] of THandle;
  i, alive, leaked: Integer;
  t0: QWord;
begin
  if not TyConPtyAvailable then
    Ignore('this Windows has no ConPTY (1809 or later is needed)');
  AssertTrue('nothing finishing from before', PtyWaitForFinishers(PtyExitWaitMs));
  alive := PtySessionsAlive;
  leaked := PtySessionsLeaked;
  FillChar(procs, SizeOf(procs), 0);
  try
    for i := 0 to High(procs) do
    begin
      b := TConPtyBackend.Create;
      s := TPtySession.Create(b);
      try
        if not s.Start('cmd.exe /d /c exit 3', 80, 24, err) then Fail('not started: ' + err);
        procs[i] := OpenProcess(SYNCHRONIZE, False, b.ProcessId);
        { 0, 20, 40 ... ms: before, while and after cmd exits }
        if i > 0 then
          Sleep(i * 20);
        t0 := GetTickCount64;
        s.Close;
        AssertTrue(Format('round %d: Close returned at once (%d ms)', [i, GetTickCount64 - t0]),
          GetTickCount64 - t0 < 200);
      finally
        s.Free;
      end;
    end;
    AssertTrue('every finisher finished', PtyWaitForFinishers(PtyExitWaitMs));
    for i := 0 to High(procs) do
      if procs[i] <> 0 then
        AssertEquals(Format('round %d: cmd is gone', [i]), WAIT_OBJECT_0, WaitForSingleObject(procs[i], 0));
    AssertEquals('nothing left behind', leaked, PtySessionsLeaked);
    AssertEquals('every session was freed', alive, PtySessionsAlive);
  finally
    for i := 0 to High(procs) do
      if procs[i] <> 0 then CloseHandle(procs[i]);
  end;
end;

{ ---- phase 7: the pipe backend (no pseudo console) ------------------------------------ }

{ run ACommand on ABackend to its end (at most 15 s); what it wrote, and AInput written
  first when given }
function RunToEnd(ACase: TTestCase; ABackend: TPtyBackend; const ACommand: string;
  const AInput: RawByteString; out AOutput: RawByteString): Int64;
var
  s: TPtySession;
  err: string;
  data: RawByteString;
  exited, ended: Boolean;
  code: Int64;

  function TheEnd: Boolean;
  begin
    if s.Pump(data, exited, code) then
    begin
      AOutput := AOutput + data;
      s.Delivered(Length(data));
      if exited then
        ended := True;
    end;
    Result := ended;
  end;

begin
  AOutput := '';
  ended := False;
  code := -2;
  s := TPtySession.Create(ABackend);
  try
    if not s.Start(ACommand, 80, 24, err) then ACase.Fail('not started: ' + err);
    if AInput <> '' then
    begin
      s.Write(AInput);
      { the program reads to its input's end: the session's close gives it that, but
        not before its output is read -- the pipe is closed by hand here }
      Sleep(200);
      ABackend.BeginClose;
    end;
    ACase.AssertTrue('the program ended within 15 s', WaitUntil(@TheEnd, 15000));
    Result := code;
  finally
    s.Free;
  end;
  ACase.AssertTrue('the finisher finished', PtyWaitForFinishers(PtyExitWaitMs));
end;

function AllBytes4: RawByteString;
var
  i: Integer;
begin
  SetLength(Result, 1024);
  for i := 0 to 1023 do
    Result[i + 1] := AnsiChar(i and 255);
end;

{ B1. The same program through ConPTY is the control: its bytes must differ, or the
  test could not tell a pseudo console from pipes. }
procedure TTyTerminalPtyTests.TestPipeBackendIsBinarySafe;
var
  got: RawByteString;
  helper: string;
begin
  helper := '"' + ParamStr(0) + '" --ty-pty-helper=';
  RunToEnd(Self, TProcessPipeBackend.Create(False), helper + 'dump', '', got);
  AssertEquals('every byte value, as written', Length(AllBytes4), Length(got));
  AssertTrue('byte for byte', got = AllBytes4);
  RunToEnd(Self, TProcessPipeBackend.Create(False), helper + 'cat', AllBytes4, got);
  AssertTrue(Format('echoed byte for byte (%d bytes)', [Length(got)]), got = AllBytes4);
  if TyConPtyAvailable then
  begin
    RunToEnd(Self, TConPtyBackend.Create, helper + 'dump', '', got);
    AssertFalse('the control: ConPTY changes them', got = AllBytes4);
  end;
end;

{ B2. Mutation: BeginClose waiting for the program on the main thread. }
procedure TTyTerminalPtyTests.TestPipeBackendCloseDoesNotWait;
var
  s: TPtySession;
  b: TProcessPipeBackend;
  err: string;
  proc: THandle;
  t0: QWord;
  build: Integer;
begin
  AssertTrue('nothing finishing from before', PtyWaitForFinishers(PtyExitWaitMs));
  b := TProcessPipeBackend.Create(False);
  s := TPtySession.Create(b);
  proc := 0;
  try
    if not s.Start('"' + ParamStr(0) + '" --ty-pty-helper=sleep', 80, 24, err) then Fail('not started: ' + err);
    AssertFalse('not a pseudo console', b.IsConPty(build));
    proc := OpenProcess(SYNCHRONIZE or PROCESS_TERMINATE, False, b.ProcessId);
    AssertTrue('the program is there', proc <> 0);
    t0 := GetTickCount64;
    s.Close;
    AssertTrue(Format('Close returned at once (%d ms)', [GetTickCount64 - t0]), GetTickCount64 - t0 < 100);
    AssertTrue('the finisher finished', PtyWaitForFinishers(9000));
    AssertEquals('the program is gone', WAIT_OBJECT_0, WaitForSingleObject(proc, 0));
  finally
    s.Free;
    if proc <> 0 then
    begin
      if WaitForSingleObject(proc, 0) <> WAIT_OBJECT_0 then
        TerminateProcess(proc, 2);
      CloseHandle(proc);
    end;
  end;
end;

{ B3. Mutation: the merge switch doing nothing. }
procedure TTyTerminalPtyTests.TestPipeBackendStderr;
var
  got: RawByteString;
  helper: string;
begin
  helper := '"' + ParamStr(0) + '" --ty-pty-helper=stderr';
  RunToEnd(Self, TProcessPipeBackend.Create(True), helper, '', got);
  AssertTrue('merged: stdout there: ' + got, Pos('ty-out', got) > 0);
  AssertTrue('merged: stderr there: ' + got, Pos('ty-err', got) > 0);
  RunToEnd(Self, TProcessPipeBackend.Create(False), helper, '', got);
  AssertTrue('apart: stdout there: ' + got, Pos('ty-out', got) > 0);
  AssertEquals('apart: stderr not', 0, Pos('ty-err', got));
end;

{$ENDIF}

initialization
  {$IFDEF MSWINDOWS}
  RunPtyHelperIfAsked;
  {$ENDIF}
  RegisterTest(TTyTerminalPtyTests);
end.
