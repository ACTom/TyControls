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

  The platform backend is passed in (the example makes TConPtyBackend or
  TUnixPtyBackend; the tests a fake), so this unit has no platform code of its own. A
  TTerminalShell runs one program: start another with a new one. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, tyControls.Terminal.Buffer, tyControls.Terminal.Core,
  tyControls.Terminal, uptysession;

resourcestring
  rsShellExited = 'Process exited with code %d';

type
  TTerminalShell = class
  private
    FTerm: TTyTerminalView;
    FSession: TPtySession;
    FRunning, FStarted, FHooked: Boolean;
    FExitCode: Integer;
    FOnData, FOnOutput: TTyTerminalDataEvent;
    FOnExit: TNotifyEvent;
    FSavedData: TTyTerminalDataEvent;
    FSavedGrid: TTyTerminalGridResizeEvent;
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
      ALow: Integer = 262144);
    destructor Destroy; override;                     { Stop }
    function Start(const ACommand: string; out AError: string): Boolean;
    procedure Stop;
    property Running: Boolean read FRunning;
    property ExitCode: Integer read FExitCode;
    { the key panel still wants to see each key's bytes }
    property OnData: TTyTerminalDataEvent read FOnData write FOnData;
    { every batch of the PTY's raw output (the example's "log PTY output") }
    property OnOutput: TTyTerminalDataEvent read FOnOutput write FOnOutput;
    { after the exit line is written }
    property OnExit: TNotifyEvent read FOnExit write FOnExit;
    { FOR THE TESTS }
    property Session: TPtySession read FSession;
  end;

implementation

constructor TTerminalShell.Create(ATerm: TTyTerminalView; ABackend: TPtyBackend; AHigh, ALow: Integer);
begin
  inherited Create;
  FTerm := ATerm;
  FSession := TPtySession.Create(ABackend, AHigh, ALow);
  FExitCode := -1;
end;

destructor TTerminalShell.Destroy;
begin
  try
    Stop;
  except
    { the session could not stop its threads (it says so on Stop); a destructor does
      not raise }
  end;
  Application.RemoveAsyncCalls(Self);
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
  if FSession <> nil then
    FSession.Close;
  Application.RemoveAsyncCalls(Self);
  if FStarted then
  begin
    Unhook;
    { what the program wrote and the terminal has not parsed yet is dropped (with the
      callbacks that would have reached a closed session) }
    FTerm.Core.DiscardPending;
  end;
  FRunning := False;
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
  code: Integer;
begin
  if (FSession = nil) or not FRunning then Exit;
  if not FSession.Pump(bytes, exited, code) then Exit;
  if bytes <> '' then
  begin
    if Assigned(FOnOutput) then FOnOutput(Self, bytes);
    FTerm.Write(bytes, @WriteDone, Length(bytes));
  end;
  { an empty write with a callback runs after everything queued before it (spec 3.1) }
  if exited then
    FTerm.Write('', @ExitDone, code);
end;

procedure TTerminalShell.TermData(Sender: TObject; const AData: RawByteString);
begin
  FSession.Write(AData);
  if Assigned(FOnData) then FOnData(Self, AData);
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
  FExitCode := ATag;
  FTerm.WriteSync(#13#10#27'[2m' + Format(rsShellExited, [FExitCode]) + #27'[0m'#13#10);
  if Assigned(FOnExit) then FOnExit(Self);
end;

end.
