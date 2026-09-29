unit uptywin;

{ The Windows PTY for the terminal example: a pseudo console (ConPTY, Windows 10 1809
  and later) with the program's input and output on two anonymous pipes.

  FPC 3.2.2's Windows unit has neither the pseudo-console calls nor the process
  attribute-list calls nor STARTUPINFOEXW, CancelSynchronousIo or RtlGetVersion; they
  are declared here. The ConPTY and attribute-list calls are looked up by name, so on an
  older Windows the example says what is missing instead of failing to start.

  - TPipeBackend reads and writes a pair of existing handles. Interrupt sets a flag
    (checked before every ReadFile) and cancels the reader's blocking ReadFile with
    CancelSynchronousIo; a cancel that lands between two reads is lost, which is why the
    session repeats Interrupt while it waits for its threads.
  - TConPtyBackend makes the pipes and the pseudo console and starts the program on it.
    A thread of its own waits for the program to exit and then closes the pseudo
    console: ConPTY keeps the output pipe open after its client is gone until then, and
    before Windows 11 24H2 ClosePseudoConsole blocks until the output is drained -- so it
    is called on that thread (or, when the user closes, while the session's reader is
    still draining), never on the main thread alone.
  - TyWindowsBuildNumber reads RtlGetVersion: GetVersionEx lies to a program without a
    compatibility manifest. The build goes to the core (Core.WindowsPty), which keeps
    xterm.js's old-ConPTY wrapping rules before build 21376. }

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
    FStop: LongInt;
    FReaderHandle: THandle;
    procedure CloseHandles;
  public
    constructor Create(AIn, AOut: THandle; AOwnsHandles: Boolean = False);
    destructor Destroy; override;
    function Start(const ACommand: string; ACols, ARows: Integer; out AError: string): Boolean; override;
    function Read(var ABuf; ACount: Integer): Integer; override;
    function Write(const ABuf; ACount: Integer): Boolean; override;
    procedure Resize(ACols, ARows: Integer); override;
    procedure Interrupt; override;
    function ExitCode(AWaitMs: Integer): Integer; override;
    procedure Shutdown; override;
    procedure BindReader(AThread: TThread); override;
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
    FWaiter: TConPtyExitWaiter;
    FLastResizeResult: HRESULT;
    procedure ClosePc;
  public
    { FOR THE TESTS: answers "no ConPTY here" when set to a function that says so }
    class var ConPtyLoader: TConPtyLoaderFunc;
    constructor Create;
    destructor Destroy; override;
    function Start(const ACommand: string; ACols, ARows: Integer; out AError: string): Boolean; override;
    procedure Resize(ACols, ARows: Integer); override;
    procedure Interrupt; override;
    function ExitCode(AWaitMs: Integer): Integer; override;
    procedure Shutdown; override;
    function IsConPty(out ABuild: Integer): Boolean; override;
    { FOR THE TESTS }
    property LastResizeResult: HRESULT read FLastResizeResult;
    property ProcessId: DWORD read FProcessId;
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
  if InterLockedExchangeAdd(FStop, 0) <> 0 then Exit(0);
  got := 0;
  { a broken pipe (the other end closed), a cancelled read, any failure: the end }
  if not ReadFile(FOut, ABuf, ACount, got, nil) then Exit(0);
  Result := got;
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
    if InterLockedExchangeAdd(FStop, 0) <> 0 then Exit(False);
    done := 0;
    if not WriteFile(FIn, p^, left, done, nil) then Exit(False);
    Inc(p, done);
    Dec(left, done);
  end;
  Result := True;
end;

procedure TPipeBackend.Resize(ACols, ARows: Integer);
begin
end;

procedure TPipeBackend.Interrupt;
begin
  InterLockedExchange(FStop, 1);
  if FReaderHandle <> 0 then
    CancelSynchronousIo(FReaderHandle);
end;

function TPipeBackend.ExitCode(AWaitMs: Integer): Integer;
begin
  Result := -1;
end;

procedure TPipeBackend.Shutdown;
begin
  CloseHandles;
end;

procedure TPipeBackend.BindReader(AThread: TThread);
begin
  FReaderHandle := AThread.Handle;
end;

{ ---- TConPtyExitWaiter -------------------------------------------------------------- }

constructor TConPtyExitWaiter.Create(AOwner: TConPtyBackend);
begin
  FOwner := AOwner;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TConPtyExitWaiter.Execute;
begin
  WaitForSingleObject(FOwner.FProcess, INFINITE);
  { the output pipe breaks once the pseudo console goes; this may block until the
    reader has drained it (before 24H2) -- which is why it is here }
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

procedure TConPtyBackend.Interrupt;
begin
  { the user closes: the program's console goes (it gets CTRL_CLOSE_EVENT) and with it
    the output pipe; the session's reader, discarding by now, drains it meanwhile }
  ClosePc;
  inherited Interrupt;
end;

function TConPtyBackend.ExitCode(AWaitMs: Integer): Integer;
var
  code: DWORD;
begin
  Result := -1;
  if FProcess = 0 then Exit;
  if WaitForSingleObject(FProcess, AWaitMs) <> WAIT_OBJECT_0 then Exit;
  code := 0;
  if GetExitCodeProcess(FProcess, code) then
    Result := Integer(code);
end;

procedure TConPtyBackend.Shutdown;
begin
  if FProcess <> 0 then
  begin
    { a program that did not go with its console within 2 s: by its handle, nothing else }
    if WaitForSingleObject(FProcess, 2000) <> WAIT_OBJECT_0 then
    begin
      TerminateProcess(FProcess, 1);
      WaitForSingleObject(FProcess, 2000);
    end;
  end;
  if FWaiter <> nil then
  begin
    FWaiter.WaitFor;
    FreeAndNil(FWaiter);
  end;
  ClosePc;
  if FProcess <> 0 then
  begin
    CloseHandle(FProcess);
    FProcess := 0;
  end;
  CloseHandles;
end;

function TConPtyBackend.IsConPty(out ABuild: Integer): Boolean;
begin
  ABuild := TyWindowsBuildNumber;
  Result := True;
end;

{$ENDIF}

end.
