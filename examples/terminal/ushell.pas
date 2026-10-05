unit ushell;

{ A shell in the terminal: a PTY session (uptysession) wired to a TTyTerminalView.

  The three things a host does, here for a real program:
    - Term.OnData          -> the session's writer thread -> the PTY (keys, pastes, the
                              terminal's own replies);
    - the PTY's output     -> Term.Write(bytes, callback, byte count): the callback tells
                              the session how much the terminal has parsed, which is
                              what holds a fast program back (the session's high and low
                              water marks) instead of the terminal's queue growing;
    - Term.OnGridResize    -> the session -> the PTY's size (the program gets SIGWINCH,
                              or ConPTY redraws).
  On Windows the core is told it sits behind ConPTY and which build (Core.WindowsPty):
  before 21376 it keeps xterm.js's old-ConPTY wrapping rules. When the program exits,
  everything it wrote is shown first, then one dim line saying so.

  When the program exits, the terminal goes back to read-only and keys go nowhere.

  The platform backend is passed in (the example makes TConPtyBackend or
  TUnixPtyBackend; the tests a fake), so this unit has no platform code of its own. A
  TTerminalShell runs one program: start another with a new one.

  Stop (and Free) returns at once: it unhooks the terminal, drops what the terminal has
  not parsed yet, closes the session -- after which no wake comes -- and removes the
  pumps already queued. Taking the program down happens on the session's own finisher
  thread (uptysession); a program that exits waits for those with PtyWaitForFinishers.

  ZMODEM (phase 7, spec 19.7): with AZmodem a TZmodemStreamHandler (uzmodemterm) sits
  on the terminal's core for the shell's life. Its bytes go out the way keys do (the
  terminal's OnData), but not into the key panel (OnData here is skipped while a stream
  is claimed: an upload is megabytes). An upload is held back while the session has
  more than 256 KB queued for the writer (CanSend). Stop cancels a transfer before it
  unhooks; the abort is queued, not waited for (the program is closed right after). A
  program that exits mid-transfer ends the transfer before the exit line is written, so
  the line is shown. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, tyControls.Terminal.Buffer, tyControls.Terminal.Core,
  tyControls.Terminal, uptysession, uzmodemterm;

resourcestring
  rsShellExited = 'Process exited with code %d';

type
  TTerminalShell = class
  private
    FTerm: TTyTerminalView;
    FSession: TPtySession;
    FRunning, FStarted, FHooked: Boolean;
    FExitCode, FPendingExitCode: Int64;
    FOnData, FOnOutput: TTyTerminalDataEvent;
    FOnExit: TNotifyEvent;
    FSavedData: TTyTerminalDataEvent;
    FSavedGrid: TTyTerminalGridResizeEvent;
    FZmodem: TZmodemStreamHandler;
    function ZmCanSend: Integer;
    procedure SessionWake(Sender: TObject);
    procedure AsyncPump(Data: PtrInt);
    procedure TermData(Sender: TObject; const AData: RawByteString);
    procedure TermGrid(Sender: TObject; ACols, ARows: Integer);
    procedure WriteDone(Sender: TObject; ATag: PtrInt);
    procedure ExitDone(Sender: TObject; ATag: PtrInt);
    procedure Unhook;
  public
    { takes ABackend over; AHigh / ALow: the session's water marks (spec 12.3) }
    constructor Create(ATerm: TTyTerminalView; ABackend: TPtyBackend; AHigh: Integer = 1048576;
      ALow: Integer = 262144; AZmodem: Boolean = False);
    destructor Destroy; override;                     { Stop }
    function Start(const ACommand: string; out AError: string): Boolean;
    procedure Stop;
    property Running: Boolean read FRunning;
    { -1 = not known; a Windows code is a DWORD (Int64: 4294967295 is not -1) }
    property ExitCode: Int64 read FExitCode;
    { the key panel still wants to see each key's bytes }
    property OnData: TTyTerminalDataEvent read FOnData write FOnData;
    { the ZModem handler (nil without AZmodem); the host wires its requests and events }
    property Zmodem: TZmodemStreamHandler read FZmodem;
    { every batch of the PTY's raw output (the example's "log PTY output") }
    property OnOutput: TTyTerminalDataEvent read FOnOutput write FOnOutput;
    { after the exit line is written }
    property OnExit: TNotifyEvent read FOnExit write FOnExit;
    { FOR THE TESTS }
    property Session: TPtySession read FSession;
    { how many pumps ran, in all shells (a class variable: counts a pump that would run
      on a freed shell too) }
    class var PumpsRun: Integer;
  end;

implementation

constructor TTerminalShell.Create(ATerm: TTyTerminalView; ABackend: TPtyBackend; AHigh, ALow: Integer;
  AZmodem: Boolean);
begin
  inherited Create;
  FTerm := ATerm;
  FSession := TPtySession.Create(ABackend, AHigh, ALow);
  FExitCode := -1;
  if AZmodem then
  begin
    FZmodem := TZmodemStreamHandler.Create(FTerm.Core);
    FZmodem.CanSend := @ZmCanSend;
  end;
end;

{ what an upload may queue now: 256 KB less what the writer has not taken yet }
function TTerminalShell.ZmCanSend: Integer;
begin
  if (FSession = nil) or not FRunning or FSession.Closed then
    Exit(0);
  Result := 256 * 1024 - FSession.PendingWrite;
end;

destructor TTerminalShell.Destroy;
begin
  try
    Stop;
  except
    { closing could not even start its finisher (no thread to be had); a destructor
      does not raise }
  end;
  Application.RemoveAsyncCalls(Self);
  FreeAndNil(FZmodem);                   { a shell that never started }
  FreeAndNil(FSession);
  inherited Destroy;
end;

function TTerminalShell.Start(const ACommand: string; out AError: string): Boolean;
var
  build: Integer;
  pty: TTyTerminalWindowsPty;
begin
  AError := '';
  Result := False;
  if FStarted then
  begin
    AError := 'this shell ran already';
    Exit;
  end;
  { before the first byte arrives (spec 12.4) }
  pty.Backend := twpNone;
  pty.BuildNumber := 0;
  if FSession.Backend.IsConPty(build) then
  begin
    pty.Backend := twpConPty;
    pty.BuildNumber := build;
  end;
  FTerm.Core.WindowsPty := pty;
  FSavedData := FTerm.OnData;
  FSavedGrid := FTerm.OnGridResize;
  FTerm.OnData := @TermData;
  FTerm.OnGridResize := @TermGrid;
  FHooked := True;
  FSession.OnWake := @SessionWake;
  if not FSession.Start(ACommand, FTerm.Cols, FTerm.Rows, AError) then
  begin
    Unhook;
    Exit;
  end;
  FTerm.ReadOnly := False;
  FStarted := True;
  FRunning := True;
  Result := True;
end;

procedure TTerminalShell.Unhook;
begin
  if not FHooked then Exit;
  FHooked := False;
  FTerm.OnData := FSavedData;
  FTerm.OnGridResize := FSavedGrid;
end;

procedure TTerminalShell.Stop;
begin
  { a transfer is cancelled while the terminal still sends to the session: its abort
    sequence is queued for the program -- but not waited for. The Close below drops
    what the writer has not taken yet, so the abort may never arrive; the program is
    taken down right after anyway (the session's finisher) }
  if FZmodem <> nil then
    FZmodem.Cancel;
  FRunning := False;
  try
    if FStarted then
    begin
      { first: no key, no resize reaches the session from here on }
      Unhook;
      { the handler goes before the core drops the queue (it would end no claim now) }
      FreeAndNil(FZmodem);
      { what the program wrote and the terminal has not parsed yet is dropped (with the
        callbacks that would have reached a closed session) }
      FTerm.Core.DiscardPending;
    end;
  finally
    try
      { returns at once; no wake after it }
      if FSession <> nil then
        FSession.Close;
    finally
      { the pumps queued before the Close }
      Application.RemoveAsyncCalls(Self);
    end;
  end;
end;

{ the reader thread: one wake per batch; the pump runs on the main thread }
procedure TTerminalShell.SessionWake(Sender: TObject);
begin
  Application.QueueAsyncCall(@AsyncPump, 0);
end;

procedure TTerminalShell.AsyncPump(Data: PtrInt);
var
  bytes: RawByteString;
  exited: Boolean;
  code: Int64;
begin
  Inc(PumpsRun);
  if (FSession = nil) or not FRunning then Exit;
  if not FSession.Pump(bytes, exited, code) then Exit;
  if bytes <> '' then
  begin
    if Assigned(FOnOutput) then FOnOutput(Self, bytes);
    FTerm.Write(bytes, @WriteDone, Length(bytes));
  end;
  { an empty write with a callback runs after everything queued before it (spec 3.1);
    the code does not ride in the tag (a PtrInt is 32 bits on 32-bit Windows) }
  if exited then
  begin
    FPendingExitCode := code;
    FTerm.Write('', @ExitDone, 0);
  end;
end;

procedure TTerminalShell.TermData(Sender: TObject; const AData: RawByteString);
begin
  { the program is gone: keys go nowhere (the terminal is read-only by now; a host
    that turns that off again still sends nothing) }
  if not FRunning then Exit;
  FSession.Write(AData);
  { a claimed stream's bytes (ZModem) are not keys: not for the key panel }
  if Assigned(FOnData) and not FTerm.StreamClaimed then FOnData(Self, AData);
end;

procedure TTerminalShell.TermGrid(Sender: TObject; ACols, ARows: Integer);
begin
  FSession.Resize(ACols, ARows);
  if Assigned(FSavedGrid) then FSavedGrid(Sender, ACols, ARows);
end;

procedure TTerminalShell.WriteDone(Sender: TObject; ATag: PtrInt);
begin
  if FSession <> nil then
    FSession.Delivered(ATag);
end;

procedure TTerminalShell.ExitDone(Sender: TObject; ATag: PtrInt);
begin
  FRunning := False;
  FExitCode := FPendingExitCode;
  { a transfer that held the stream ends first (its abort goes nowhere now): else the
    exit line would go into the claim and the terminal stay claimed until it timed out }
  if FZmodem <> nil then
    FZmodem.Cancel;
  FTerm.ReadOnly := True;
  FTerm.WriteSync(#13#10#27'[2m' + Format(rsShellExited, [FExitCode]) + #27'[0m'#13#10);
  if Assigned(FOnExit) then FOnExit(Self);
end;

end.
