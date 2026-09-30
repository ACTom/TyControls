unit uptywin;

{ The Windows PTY for the terminal example: a pseudo console (ConPTY, Windows 10 1809
  and later) with the program's input and output on two anonymous pipes.

  FPC 3.2.2's Windows unit has neither the pseudo-console calls nor the process
  attribute-list calls nor STARTUPINFOEXW, CancelSynchronousIo or RtlGetVersion; they
  are declared here. The ConPTY and attribute-list calls are looked up by name, so on an
  older Windows the example says what is missing instead of failing to start.

  - TPipeBackend reads and writes a pair of existing handles. Interrupt sets two flags
    (checked before every ReadFile / WriteFile) and cancels the threads' blocking calls
    with CancelSynchronousIo; a cancel that lands between two calls is lost, which is
    why the session's finisher repeats Interrupt while it waits for its threads. A cancel
    that is not ours (no flag set) is retried, not read as the end.
  - TConPtyBackend makes the pipes and the pseudo console and starts the program on it.
    ClosePseudoConsole is called on one thread only, the backend's exit waiter: it waits
    for the program to exit OR for the close event, then closes the pseudo console.
    ConPTY keeps the output pipe open after its program is gone until then, and before
    Windows 11 24H2 ClosePseudoConsole blocks until the output is drained and the
    program has gone -- a program in its close handler may take five seconds, and it
    was measured blocking the main thread on build 19044. So closing (BeginClose, main
    thread) only sets the event and cancels a blocked write; the session's finisher
    waits for the waiter (FinishClose), ends the program by its handle when it does not
    go in time -- which also lets ClosePseudoConsole return -- and the session's reader
    drains the output all along.
  - TyWindowsBuildNumber reads RtlGetVersion: GetVersionEx lies to a program without a
    compatibility manifest. The build goes to the core (Core.WindowsPty), which keeps
    xterm.js's old-ConPTY wrapping rules before build 21376.
  - TProcessPipeBackend (phase 7, spec 19.7): the command on two anonymous pipes, no
    pseudo console -- binary safe, which ConPTY is not (it renders the output anew
    and drops every byte from $80 up, both ways: the phase 7 plan's Task 0). For
    ZModem through wsl.exe or ssh -T. There is no terminal: the program sees pipes,
    does not echo, cannot be resized; stderr goes into the same pipe unless asked not
    to. Closing sends EOF (the input pipe's end closed), then the session's finisher
    waits and ends the program by its handle, as for ConPTY -- never on the main
    thread. }

{$mode objfpc}{$H+}

interface

{$IFDEF MSWINDOWS}
uses
  Windows, Classes, SysUtils, SyncObjs, uptysession;

resourcestring
  rsConPtyUnavailable = 'This version of Windows has no pseudo console (ConPTY); Windows 10 1809 or later is needed.';

type
  HPCON = THandle;
  TConPtyLoaderFunc = function: Boolean;

  { A pair of pipe handles: AIn is written (the program's input), AOut is read. }
  TPipeBackend = class(TPtyBackend)
  protected
    FIn, FOut: THandle;
    FOwnsHandles: Boolean;
    FStopRead, FStopWrite: LongInt;
    FReaderHandle, FWriterHandle: THandle;
    procedure CloseHandles;
    procedure StopWrites;
  public
    constructor Create(AIn, AOut: THandle; AOwnsHandles: Boolean = False);
    destructor Destroy; override;
    function Start(const ACommand: string; ACols, ARows: Integer; out AError: string): Boolean; override;
    function Read(var ABuf; ACount: Integer): Integer; override;
    function Write(const ABuf; ACount: Integer): Boolean; override;
    procedure Resize(ACols, ARows: Integer); override;
    procedure Interrupt; override;
    function ExitCode(AWaitMs: Integer): Int64; override;
    procedure Shutdown; override;
    procedure BindThreads(AReader, AWriter: TThread); override;
  end;

  TConPtyBackend = class;

  TConPtyExitWaiter = class(TThread)
  private
    FOwner: TConPtyBackend;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TConPtyBackend);
  end;

  TConPtyBackend = class(TPipeBackend)
  private
    FPC: HPCON;
    FLock: TCriticalSection;
    FProcess: THandle;
    FProcessId: DWORD;
    FCloseEvent: THandle;
    FWaiter: TConPtyExitWaiter;
    FWaiterStuck: Boolean;
    FKilled: Boolean;
    FLastResizeResult: HRESULT;
    procedure ClosePc;
    function WaiterGone(AWaitMs: DWORD): Boolean;
  public
    { FOR THE TESTS: answers "no ConPTY here" when set to a function that says so }
    class var ConPtyLoader: TConPtyLoaderFunc;
    constructor Create;
    destructor Destroy; override;
    function Start(const ACommand: string; ACols, ARows: Integer; out AError: string): Boolean; override;
    procedure Resize(ACols, ARows: Integer); override;
    procedure BeginClose; override;
    function FinishClose(AWaitMs: Integer): TPtyCloseResult; override;
    function ExitCode(AWaitMs: Integer): Int64; override;
    procedure Shutdown; override;
    function IsConPty(out ABuild: Integer): Boolean; override;
    { FOR THE TESTS }
    property LastResizeResult: HRESULT read FLastResizeResult;
    property ProcessId: DWORD read FProcessId;
    property Killed: Boolean read FKilled;
  end;

  { a command on two anonymous pipes, no pseudo console (spec 19.7): binary safe }
  TProcessPipeBackend = class(TPipeBackend)
  private
    FMergeStderr: Boolean;
    FProcess: THandle;
    FProcessId: DWORD;
    FKilled: Boolean;
  public
    constructor Create(AMergeStderr: Boolean = True);
    destructor Destroy; override;
    function Start(const ACommand: string; ACols, ARows: Integer; out AError: string): Boolean; override;
    procedure Resize(ACols, ARows: Integer); override;       { nothing }
    procedure BeginClose; override;                          { closes the input pipe }
    function FinishClose(AWaitMs: Integer): TPtyCloseResult; override;
    function ExitCode(AWaitMs: Integer): Int64; override;
    procedure Shutdown; override;
    { FOR THE TESTS }
    property ProcessId: DWORD read FProcessId;
    property Killed: Boolean read FKilled;
  end;

{ dwBuildNumber from RtlGetVersion; 0 when it cannot be had }
function TyWindowsBuildNumber: Integer;
{ the pseudo-console calls are there }
function TyConPtyAvailable: Boolean;
{$ENDIF}

implementation

{$IFDEF MSWINDOWS}

type
  { FPC 3.2.2 has none of these }
  STARTUPINFOEXW = record
    StartupInfo: TStartupInfoW;
    lpAttributeList: Pointer;
  end;
  TRtlOsVersionInfoExW = record
    dwOSVersionInfoSize, dwMajorVersion, dwMinorVersion, dwBuildNumber, dwPlatformId: DWORD;
    szCSDVersion: array[0..127] of WideChar;
    wServicePackMajor, wServicePackMinor, wSuiteMask: Word;
    wProductType, wReserved: Byte;
  end;
  { COORD is a 4-byte struct passed by value: packed into a DWORD here (rows high,
    columns low) instead of relying on how a small record is passed }
  TCreatePseudoConsole = function(ASize: DWORD; hInput, hOutput: THandle; dwFlags: DWORD;
    out phPC: HPCON): HRESULT; stdcall;
  TResizePseudoConsole = function(hPC: HPCON; ASize: DWORD): HRESULT; stdcall;
  TClosePseudoConsole = procedure(hPC: HPCON); stdcall;
  TInitializeProcThreadAttributeList = function(lpAttributeList: Pointer; dwAttributeCount, dwFlags: DWORD;
    var lpSize: SIZE_T): BOOL; stdcall;
  TUpdateProcThreadAttribute = function(lpAttributeList: Pointer; dwFlags: DWORD; Attribute: DWORD_PTR;
    lpValue: Pointer; cbSize: SIZE_T; lpPreviousValue: Pointer; lpReturnSize: Pointer): BOOL; stdcall;
  TDeleteProcThreadAttributeList = procedure(lpAttributeList: Pointer); stdcall;
  TRtlGetVersion = function(var AInfo: TRtlOsVersionInfoExW): LongInt; stdcall;

const
  PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE = $00020016;

function CancelSynchronousIo(hThread: THandle): BOOL; stdcall; external 'kernel32' name 'CancelSynchronousIo';

var
  PCreatePseudoConsole: TCreatePseudoConsole;
  PResizePseudoConsole: TResizePseudoConsole;
  PClosePseudoConsole: TClosePseudoConsole;
  PInitializeProcThreadAttributeList: TInitializeProcThreadAttributeList;
  PUpdateProcThreadAttribute: TUpdateProcThreadAttribute;
  PDeleteProcThreadAttributeList: TDeleteProcThreadAttributeList;

function LoadConPtyByName: Boolean;
var
  k: HMODULE;
begin
  k := GetModuleHandle('kernel32.dll');
  if k = 0 then Exit(False);
  Pointer(PCreatePseudoConsole) := GetProcAddress(k, 'CreatePseudoConsole');
  Pointer(PResizePseudoConsole) := GetProcAddress(k, 'ResizePseudoConsole');
  Pointer(PClosePseudoConsole) := GetProcAddress(k, 'ClosePseudoConsole');
  Pointer(PInitializeProcThreadAttributeList) := GetProcAddress(k, 'InitializeProcThreadAttributeList');
  Pointer(PUpdateProcThreadAttribute) := GetProcAddress(k, 'UpdateProcThreadAttribute');
  Pointer(PDeleteProcThreadAttributeList) := GetProcAddress(k, 'DeleteProcThreadAttributeList');
  Result := Assigned(PCreatePseudoConsole) and Assigned(PResizePseudoConsole) and Assigned(PClosePseudoConsole)
    and Assigned(PInitializeProcThreadAttributeList) and Assigned(PUpdateProcThreadAttribute)
    and Assigned(PDeleteProcThreadAttributeList);
end;

function LoadConPty: Boolean;
begin
  if Assigned(TConPtyBackend.ConPtyLoader) then
    Result := TConPtyBackend.ConPtyLoader() and LoadConPtyByName
  else
    Result := LoadConPtyByName;
end;

function TyConPtyAvailable: Boolean;
begin
  Result := LoadConPty;
end;

function TyWindowsBuildNumber: Integer;
var
  f: TRtlGetVersion;
  info: TRtlOsVersionInfoExW;
  nt: HMODULE;
begin
  Result := 0;
  nt := GetModuleHandle('ntdll.dll');
  if nt = 0 then Exit;
  Pointer(f) := GetProcAddress(nt, 'RtlGetVersion');
  if not Assigned(f) then Exit;
  FillChar(info, SizeOf(info), 0);
  info.dwOSVersionInfoSize := SizeOf(info);
  if f(info) = 0 then
    Result := info.dwBuildNumber;
end;

{ ---- TPipeBackend ------------------------------------------------------------------- }

constructor TPipeBackend.Create(AIn, AOut: THandle; AOwnsHandles: Boolean);
begin
  inherited Create;
  FIn := AIn;
  FOut := AOut;
  FOwnsHandles := AOwnsHandles;
end;

destructor TPipeBackend.Destroy;
begin
  CloseHandles;
  inherited Destroy;
end;

procedure TPipeBackend.CloseHandles;
begin
  if not FOwnsHandles then Exit;
  if FIn <> 0 then CloseHandle(FIn);
  if FOut <> 0 then CloseHandle(FOut);
  FIn := 0;
  FOut := 0;
end;

function TPipeBackend.Start(const ACommand: string; ACols, ARows: Integer; out AError: string): Boolean;
begin
  AError := '';
  Result := True;
end;

function TPipeBackend.Read(var ABuf; ACount: Integer): Integer;
var
  got: DWORD;
begin
  while True do
  begin
    if InterLockedExchangeAdd(FStopRead, 0) <> 0 then Exit(0);
    got := 0;
    if ReadFile(FOut, ABuf, ACount, got, nil) then
      Exit(got);
    { a cancel that is not ours (the write side's, say): read on. A broken pipe (the
      other end closed), our cancel, any other failure: the end }
    if (GetLastError = ERROR_OPERATION_ABORTED) and (InterLockedExchangeAdd(FStopRead, 0) = 0) then
      Continue;
    Exit(0);
  end;
end;

function TPipeBackend.Write(const ABuf; ACount: Integer): Boolean;
var
  p: PByte;
  left: Integer;
  done: DWORD;
begin
  p := @ABuf;
  left := ACount;
  while left > 0 do
  begin
    if InterLockedExchangeAdd(FStopWrite, 0) <> 0 then Exit(False);
    done := 0;
    if not WriteFile(FIn, p^, left, done, nil) then
    begin
      if (GetLastError = ERROR_OPERATION_ABORTED) and (InterLockedExchangeAdd(FStopWrite, 0) = 0) then
        Continue;
      Exit(False);
    end;
    Inc(p, done);
    Dec(left, done);
  end;
  Result := True;
end;

procedure TPipeBackend.Resize(ACols, ARows: Integer);
begin
end;

{ a writer blocked in WriteFile (the program reads no input, the pipe is full) returns }
procedure TPipeBackend.StopWrites;
begin
  InterLockedExchange(FStopWrite, 1);
  if FWriterHandle <> 0 then
    CancelSynchronousIo(FWriterHandle);
end;

procedure TPipeBackend.Interrupt;
begin
  InterLockedExchange(FStopRead, 1);
  if FReaderHandle <> 0 then
    CancelSynchronousIo(FReaderHandle);
  StopWrites;
end;

function TPipeBackend.ExitCode(AWaitMs: Integer): Int64;
begin
  Result := -1;
end;

procedure TPipeBackend.Shutdown;
begin
  CloseHandles;
end;

procedure TPipeBackend.BindThreads(AReader, AWriter: TThread);
begin
  FReaderHandle := AReader.Handle;
  FWriterHandle := AWriter.Handle;
end;

{ ---- TConPtyExitWaiter -------------------------------------------------------------- }

constructor TConPtyExitWaiter.Create(AOwner: TConPtyBackend);
begin
  FOwner := AOwner;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TConPtyExitWaiter.Execute;
var
  hs: array[0..1] of THandle;
begin
  { the program exits, or the user closes: either way the pseudo console goes, and with
    it the output pipe (the reader then reads the end). This may block until the reader
    has drained the output and the program has gone (before 24H2) -- which is why it is
    here, on no thread anything waits for unbounded }
  hs[0] := FOwner.FProcess;
  hs[1] := FOwner.FCloseEvent;
  WaitForMultipleObjects(2, PWOHandleArray(@hs[0]), False, INFINITE);
  FOwner.ClosePc;
end;

{ ---- TConPtyBackend ------------------------------------------------------------------ }

constructor TConPtyBackend.Create;
begin
  inherited Create(0, 0, True);
  FLock := TCriticalSection.Create;
end;

destructor TConPtyBackend.Destroy;
begin
  Shutdown;
  { a waiter stuck in ClosePseudoConsole keeps FLock: the session leaks the backend
    instead of freeing it, so this is not reached then }
  FreeAndNil(FLock);
  inherited Destroy;
end;

procedure TConPtyBackend.ClosePc;
var
  pc: HPCON;
begin
  FLock.Enter;
  try
    pc := FPC;
    FPC := 0;
  finally
    FLock.Leave;
  end;
  if pc <> 0 then
    PClosePseudoConsole(pc);
end;

function TConPtyBackend.Start(const ACommand: string; ACols, ARows: Integer; out AError: string): Boolean;
var
  inRead, inWrite, outRead, outWrite: THandle;
  hr: HRESULT;
  size: SIZE_T;
  list: Pointer;
  si: STARTUPINFOEXW;
  pi: TProcessInformation;
  cmd: UnicodeString;
begin
  AError := '';
  Result := False;
  if not LoadConPty then
  begin
    AError := rsConPtyUnavailable;
    Exit;
  end;
  inRead := 0; inWrite := 0; outRead := 0; outWrite := 0;
  if not CreatePipe(inRead, inWrite, nil, 0) or not CreatePipe(outRead, outWrite, nil, 0) then
  begin
    AError := SysErrorMessage(GetLastError);
    if inRead <> 0 then CloseHandle(inRead);
    if inWrite <> 0 then CloseHandle(inWrite);
    Exit;
  end;
  hr := PCreatePseudoConsole((DWORD(ARows and $FFFF) shl 16) or DWORD(ACols and $FFFF), inRead, outWrite, 0, FPC);
  { the pseudo console has its own copies of these two }
  CloseHandle(inRead);
  CloseHandle(outWrite);
  if hr <> S_OK then
  begin
    AError := SysErrorMessage(hr and $FFFF);
    CloseHandle(inWrite);
    CloseHandle(outRead);
    FPC := 0;
    Exit;
  end;
  FIn := inWrite;
  FOut := outRead;
  { the attribute list with the pseudo console in it (two calls: the size, then the list) }
  size := 0;
  PInitializeProcThreadAttributeList(nil, 1, 0, size);
  GetMem(list, size);
  try
    if not PInitializeProcThreadAttributeList(list, 1, 0, size) then
    begin
      AError := SysErrorMessage(GetLastError);
      ClosePc;
      CloseHandles;
      Exit;
    end;
    try
      { the value is the handle itself, not a pointer to it }
      if not PUpdateProcThreadAttribute(list, 0, PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE, Pointer(FPC),
        SizeOf(HPCON), nil, nil) then
      begin
        AError := SysErrorMessage(GetLastError);
        ClosePc;
        CloseHandles;
        Exit;
      end;
      FillChar(si, SizeOf(si), 0);
      si.StartupInfo.cb := SizeOf(STARTUPINFOEXW);
      si.lpAttributeList := list;
      { with no standard handles given, a program whose own are redirected (a pipe or a
        file: the test runner's output) hands them to the child, and the child writes
        there instead of into the pseudo console; empty ones make it use the console's }
      si.StartupInfo.dwFlags := STARTF_USESTDHANDLES;
      FillChar(pi, SizeOf(pi), 0);
      cmd := UTF8Decode(ACommand);
      UniqueString(cmd);
      if not CreateProcessW(nil, PWideChar(cmd), nil, nil, False, EXTENDED_STARTUPINFO_PRESENT, nil, nil,
        @si.StartupInfo, @pi) then
      begin
        AError := SysErrorMessage(GetLastError);
        ClosePc;
        CloseHandles;
        Exit;
      end;
    finally
      PDeleteProcThreadAttributeList(list);
    end;
  finally
    FreeMem(list);
  end;
  CloseHandle(pi.hThread);
  FProcess := pi.hProcess;
  FProcessId := pi.dwProcessId;
  FCloseEvent := CreateEvent(nil, True, False, nil);
  FWaiter := TConPtyExitWaiter.Create(Self);
  Result := True;
end;

procedure TConPtyBackend.Resize(ACols, ARows: Integer);
begin
  FLock.Enter;
  try
    if FPC <> 0 then
      FLastResizeResult := PResizePseudoConsole(FPC, (DWORD(ARows and $FFFF) shl 16) or DWORD(ACols and $FFFF));
  finally
    FLock.Leave;
  end;
end;

{ the main thread: the waiter closes the pseudo console (the program gets
  CTRL_CLOSE_EVENT); a blocked write returns. The reader goes on draining. }
procedure TConPtyBackend.BeginClose;
begin
  if FCloseEvent <> 0 then
    SetEvent(FCloseEvent);
  StopWrites;
end;

function TConPtyBackend.WaiterGone(AWaitMs: DWORD): Boolean;
begin
  Result := (FWaiter = nil) or (WaitForSingleObject(FWaiter.Handle, AWaitMs) = WAIT_OBJECT_0);
end;

function TConPtyBackend.FinishClose(AWaitMs: Integer): TPtyCloseResult;
var
  t0, spent: QWord;
  left: DWORD;
begin
  Result := pcrGone;
  if FProcess = 0 then Exit;
  { 1. the pseudo console closes and the program goes, both within AWaitMs }
  t0 := GetTickCount64;
  WaiterGone(AWaitMs);
  spent := GetTickCount64 - t0;
  if spent >= QWord(AWaitMs) then left := 0 else left := AWaitMs - spent;
  if WaitForSingleObject(FProcess, left) = WAIT_OBJECT_0 then
  begin
    if WaiterGone(PtyKillWaitMs) then Exit;
  end
  else
  begin
    { 2. it did not: by its handle, nothing else (never by name) -- this also lets a
      blocked ClosePseudoConsole return }
    FKilled := True;
    Result := pcrKilled;
    TerminateProcess(FProcess, 1);
    WaitForSingleObject(FProcess, PtyKillWaitMs);
    if WaiterGone(PtyKillWaitMs) then Exit;
  end;
  { 3. ClosePseudoConsole still has not returned: what it uses stays }
  FWaiterStuck := True;
  Result := pcrStuck;
end;

function TConPtyBackend.ExitCode(AWaitMs: Integer): Int64;
var
  code: DWORD;
begin
  Result := -1;
  if FProcess = 0 then Exit;
  if WaitForSingleObject(FProcess, AWaitMs) <> WAIT_OBJECT_0 then Exit;
  code := 0;
  if GetExitCodeProcess(FProcess, code) then
    Result := code;                            { a DWORD, never -1 }
end;

procedure TConPtyBackend.Shutdown;
begin
  { reached after FinishClose (the waiter is gone), or for a backend that never
    started; a program still there (freed without FinishClose) goes by its handle }
  if (FProcess <> 0) and (WaitForSingleObject(FProcess, 0) <> WAIT_OBJECT_0) then
  begin
    TerminateProcess(FProcess, 1);
    WaitForSingleObject(FProcess, PtyKillWaitMs);
  end;
  if FCloseEvent <> 0 then
    SetEvent(FCloseEvent);
  if FWaiter <> nil then
  begin
    if FWaiterStuck or not WaiterGone(PtyKillWaitMs) then
      Exit;                                    { leave it and its handles (unit header) }
    FreeAndNil(FWaiter);
  end;
  ClosePc;
  if FProcess <> 0 then
  begin
    CloseHandle(FProcess);
    FProcess := 0;
  end;
  if FCloseEvent <> 0 then
  begin
    CloseHandle(FCloseEvent);
    FCloseEvent := 0;
  end;
  CloseHandles;
end;

function TConPtyBackend.IsConPty(out ABuild: Integer): Boolean;
begin
  ABuild := TyWindowsBuildNumber;
  Result := True;
end;

{ ---- TProcessPipeBackend ---------------------------------------------------------------- }

constructor TProcessPipeBackend.Create(AMergeStderr: Boolean);
begin
  inherited Create(0, 0, True);
  FMergeStderr := AMergeStderr;
end;

destructor TProcessPipeBackend.Destroy;
begin
  Shutdown;
  inherited Destroy;
end;

function TProcessPipeBackend.Start(const ACommand: string; ACols, ARows: Integer; out AError: string): Boolean;
var
  sa: TSecurityAttributes;
  inRead, inWrite, outRead, outWrite, errH: THandle;
  si: TStartupInfoW;
  pi: TProcessInformation;
  cmd: UnicodeString;
begin
  AError := '';
  Result := False;
  FillChar(sa, SizeOf(sa), 0);
  sa.nLength := SizeOf(sa);
  sa.bInheritHandle := True;
  inRead := 0; inWrite := 0; outRead := 0; outWrite := 0; errH := 0;
  if not CreatePipe(inRead, inWrite, @sa, 0) or not CreatePipe(outRead, outWrite, @sa, 0) then
  begin
    AError := SysErrorMessage(GetLastError);
    if inRead <> 0 then CloseHandle(inRead);
    if inWrite <> 0 then CloseHandle(inWrite);
    Exit;
  end;
  { our ends are not the child's to inherit }
  SetHandleInformation(inWrite, HANDLE_FLAG_INHERIT, 0);
  SetHandleInformation(outRead, HANDLE_FLAG_INHERIT, 0);
  if FMergeStderr then
    errH := outWrite
  else
    errH := CreateFileW('NUL', GENERIC_WRITE, FILE_SHARE_READ or FILE_SHARE_WRITE, @sa, OPEN_EXISTING, 0, 0);
  FillChar(si, SizeOf(si), 0);
  si.cb := SizeOf(si);
  si.dwFlags := STARTF_USESTDHANDLES;
  si.hStdInput := inRead;
  si.hStdOutput := outWrite;
  si.hStdError := errH;
  FillChar(pi, SizeOf(pi), 0);
  cmd := UTF8Decode(ACommand);
  UniqueString(cmd);
  if not CreateProcessW(nil, PWideChar(cmd), nil, nil, True, CREATE_NO_WINDOW or CREATE_UNICODE_ENVIRONMENT,
    nil, nil, @si, @pi) then
  begin
    AError := SysErrorMessage(GetLastError);
    CloseHandle(inRead);
    CloseHandle(outWrite);
    if not FMergeStderr and (errH <> INVALID_HANDLE_VALUE) then CloseHandle(errH);
    CloseHandle(inWrite);
    CloseHandle(outRead);
    Exit;
  end;
  { the child's ends: only the child holds them now, so its exit ends our read }
  CloseHandle(inRead);
  CloseHandle(outWrite);
  if not FMergeStderr and (errH <> INVALID_HANDLE_VALUE) then CloseHandle(errH);
  CloseHandle(pi.hThread);
  FProcess := pi.hProcess;
  FProcessId := pi.dwProcessId;
  FIn := inWrite;
  FOut := outRead;
  Result := True;
end;

procedure TProcessPipeBackend.Resize(ACols, ARows: Integer);
begin
  { a pipe has no size }
end;

{ the main thread, quick: a blocked write returns, the program reads EOF. The handle
  is taken out of FIn before it is closed: the writer, stopped already, fails on 0 }
procedure TProcessPipeBackend.BeginClose;
var
  h: THandle;
begin
  StopWrites;
  h := FIn;
  FIn := 0;
  if h <> 0 then
    CloseHandle(h);
end;

function TProcessPipeBackend.FinishClose(AWaitMs: Integer): TPtyCloseResult;
begin
  Result := pcrGone;
  if FProcess = 0 then Exit;
  if WaitForSingleObject(FProcess, AWaitMs) = WAIT_OBJECT_0 then
    Exit;
  { it did not go with its input: by its handle, nothing else (never by name) }
  FKilled := True;
  Result := pcrKilled;
  TerminateProcess(FProcess, 1);
  WaitForSingleObject(FProcess, PtyKillWaitMs);
end;

function TProcessPipeBackend.ExitCode(AWaitMs: Integer): Int64;
var
  code: DWORD;
begin
  Result := -1;
  if FProcess = 0 then Exit;
  if WaitForSingleObject(FProcess, AWaitMs) <> WAIT_OBJECT_0 then Exit;
  code := 0;
  if GetExitCodeProcess(FProcess, code) then
    Result := code;
end;

procedure TProcessPipeBackend.Shutdown;
begin
  if FProcess <> 0 then
  begin
    if WaitForSingleObject(FProcess, 0) <> WAIT_OBJECT_0 then
    begin
      TerminateProcess(FProcess, 1);
      WaitForSingleObject(FProcess, PtyKillWaitMs);
    end;
    CloseHandle(FProcess);
    FProcess := 0;
  end;
  CloseHandles;
end;

{$ENDIF}

end.
