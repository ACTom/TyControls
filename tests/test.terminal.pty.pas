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
  loop, so a broken session fails a test instead of hanging the run. }

interface

uses
  Classes, SysUtils, SyncObjs, Forms, Controls, LCLType, fpcunit, testregistry,
  tyControls.Terminal.Buffer, tyControls.Terminal.Core, tyControls.Terminal,
  uptysession, ushell, test.terminal.view;

type
  { A PTY that is not one. }
  TFakePty = class(TPtyBackend)
  private
    FLock: TCriticalSection;
    FEvent: TEvent;
    FPending: RawByteString;
    FEof: Boolean;
    FEofCode: Integer;
    FInterrupted: Boolean;
    FWritten: RawByteString;
    FResizeCols, FResizeRows, FResizes: Integer;
    FReads: Integer;
    FSent: Int64;
  public
    Endless: Boolean;
    EndlessLimit: Int64;             { 0 = without end }
    ConPty: Boolean;
    Build: Integer;
    StartResult: Boolean;
    constructor Create;
    destructor Destroy; override;
    function Start(const ACommand: string; ACols, ARows: Integer; out AError: string): Boolean; override;
    function Read(var ABuf; ACount: Integer): Integer; override;
    function Write(const ABuf; ACount: Integer): Boolean; override;
    procedure Resize(ACols, ARows: Integer); override;
    procedure Interrupt; override;
    function ExitCode(AWaitMs: Integer): Integer; override;
    procedure Shutdown; override;
    function IsConPty(out ABuild: Integer): Boolean; override;
    procedure Feed(const S: RawByteString);
    procedure FeedEof(ACode: Integer);
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
  end;

implementation

type
  TWaitCheck = function: Boolean is nested;

{ ---- TFakePty ---------------------------------------------------------------------- }

constructor TFakePty.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FEvent := TEvent.Create(nil, False, False, '');
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
    Result := not FInterrupted;
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

function TFakePty.ExitCode(AWaitMs: Integer): Integer;
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

procedure TFakePty.FeedEof(ACode: Integer);
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
    Result := Point(FResizeCols, FResizeRows);
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
  code: Integer;

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
  code, before: Integer;

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

procedure TTyTerminalPtyTests.TestCloseDoesNotHang;
var
  fake: TFakePty;
  s: TPtySession;
  sh: TTerminalShell;
  err: string;
  t0: QWord;
begin
  fake := TFakePty.Create;
  s := TPtySession.Create(fake);
  try
    AssertTrue('started', s.Start('fake', 80, 24, err));
    Sleep(50);                                 { the reader is waiting in Read }
    t0 := GetTickCount64;
    s.Close;
    AssertTrue(Format('closed within a second (%d ms)', [GetTickCount64 - t0]), GetTickCount64 - t0 < 1000);
    AssertTrue('both threads are gone', s.ThreadsFinished);
    s.Close;                                   { again: nothing }
  finally
    s.Free;
  end;
  { a shell freed with a pump still queued }
  fake := TFakePty.Create;
  sh := TTerminalShell.Create(F.View, fake);
  AssertTrue('started', sh.Start('fake', err));
  fake.Feed('queued');
  Sleep(100);                                  { the wake is queued, not run }
  sh.Free;
  Application.ProcessMessages;                 { would run the freed shell's pump }
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
    AssertTrue(Format('closed within a second (%d ms)', [GetTickCount64 - t0]), GetTickCount64 - t0 < 1000);
  finally
    s.Free;
  end;
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

initialization
  RegisterTest(TTyTerminalPtyTests);
end.
