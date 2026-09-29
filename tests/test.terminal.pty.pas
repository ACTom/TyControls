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
  ended by its handle if it does not go with its console). }

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
    FEofCode: Integer;
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
    {$IFDEF MSWINDOWS}
    procedure TestPipesRoundTrip;
    procedure TestInterruptUnblocksARead;
    procedure TestTheBuildNumberIsTheRealOne;
    procedure TestNoConPtyIsReported;
    procedure TestConPtyRunsACommand;
    procedure TestConPtyResizesAndCloses;
    {$ENDIF}
  end;

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
  code: Integer;
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
    AssertTrue(Format('the blocked read was cancelled (%d ms)', [GetTickCount64 - t0]), GetTickCount64 - t0 < 1000);
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
  code, endCode: Integer;

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
    AssertTrue('started: ' + err, s.Start('cmd.exe /d /c echo tyterm-ok& exit 7', 80, 24, err));
    all := '';
    ended := False;
    endCode := -2;
    AssertTrue('the program ended within 10 s', WaitUntil(@TheEnd, 10000));
    AssertTrue('its output came through: ' + StripEscapes(all), Pos('tyterm-ok', StripEscapes(all)) > 0);
    AssertEquals('its exit code', 7, endCode);
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
    AssertTrue('started: ' + err, s.Start('cmd.exe /d /k', 80, 24, err));
    proc := OpenProcess(SYNCHRONIZE, False, b.ProcessId);
    AssertTrue('the program is there', proc <> 0);
    s.Resize(100, 40);
    AssertEquals('ResizePseudoConsole succeeded', 0, b.LastResizeResult);
    t0 := GetTickCount64;
    s.Close;
    AssertTrue(Format('closed within 5 s (%d ms)', [GetTickCount64 - t0]), GetTickCount64 - t0 < 5000);
    AssertEquals('the program is gone', WAIT_OBJECT_0, WaitForSingleObject(proc, 0));
  finally
    s.Free;
    if proc <> 0 then CloseHandle(proc);
  end;
end;

{$ENDIF}

initialization
  RegisterTest(TTyTerminalPtyTests);
end.
