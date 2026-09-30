unit test.terminal.zmodem.wsl;
{$mode objfpc}{$H+}
{$modeswitch nestedprocvars}
{ The terminal example's ZMODEM against the real lrzsz (7 期, spec 19.9): sz and rz in
  WSL Ubuntu, started through the example's pipe backend (TProcessPipeBackend: no
  pseudo console, bytes as they are), with the core, the stream hook and the glue all
  real -- only the form is missing, so the requests are answered at once and the
  loop here pumps the session into the core as the example's message loop does.

  Without Windows, wsl.exe, the Ubuntu distribution or lrzsz in it, every test is
  ignored with the reason. After each case the sz / rz left in WSL are ended there
  (pkill in the distribution, never a Windows process by name).

  I1-I11 of the phase 7 plan. The WSL console tool tools/terminal-zmodem-wsl runs the
  same kind of transfers through the Unix PTY backend. }

interface

uses
  Classes, SysUtils, fpcunit, testregistry;

type
  TTyTerminalZmodemWslTests = class(TTestCase)
  private
    procedure NeedWsl;
  published
    procedure TestDownloadSmallFiles;                        { I1 }
    procedure TestDownloadEveryByteValue;                    { I2 }
    procedure TestDownloadABigFile;                          { I3 }
    procedure TestDownloadThreeAtOnce;                       { I4 }
    procedure TestDownloadBigBlocksAndAWindow;               { I5 }
    procedure TestDownloadWithADamagedByte;                  { I6 }
    procedure TestWhatFollowsTheDownload;                    { I7 }
    procedure TestCancellingADownload;                       { I8 }
    procedure TestUploads;                                   { I9 }
    procedure TestUploadWithADamagedByte;                    { I10 }
    procedure TestCancellingAnUpload;                        { I11 }
  end;

implementation

{$IFDEF MSWINDOWS}
uses
  Windows, SyncObjs, Math, md5, tyControls.Terminal.Buffer, tyControls.Terminal.Core,
  uptysession, uptywin, uzmodem, uzmodemsession, uzmodemterm;

var
  GChecked: Boolean = False;
  GReason: string = '';

type
  TWaker = class
  public
    Event: TEvent;
    constructor Create;
    destructor Destroy; override;
    procedure Wake(Sender: TObject);
  end;

constructor TWaker.Create;
begin
  inherited Create;
  Event := TEvent.Create(nil, False, False, '');
end;

destructor TWaker.Destroy;
begin
  Event.Free;
  inherited Destroy;
end;

procedure TWaker.Wake(Sender: TObject);
begin
  Event.SetEvent;
end;

{ a command on the pipe backend to its end, its output (at most ATimeoutMs) }
function RunPlain(const ACommand: string; ATimeoutMs: Integer; out AOutput: RawByteString): Int64;
var
  waker: TWaker;
  s: TPtySession;
  err: string;
  data: RawByteString;
  exited: Boolean;
  code: Int64;
  t0: QWord;
begin
  AOutput := '';
  Result := -2;
  waker := TWaker.Create;
  s := TPtySession.Create(TProcessPipeBackend.Create(False));
  try
    s.OnWake := @waker.Wake;
    if not s.Start(ACommand, 80, 24, err) then
    begin
      AOutput := err;
      Exit(-3);
    end;
    t0 := GetTickCount64;
    while GetTickCount64 - t0 < QWord(ATimeoutMs) do
    begin
      waker.Event.WaitFor(50);
      if s.Pump(data, exited, code) then
      begin
        AOutput := AOutput + data;
        s.Delivered(Length(data));
        if exited then
          Exit(code);
      end;
    end;
  finally
    s.Free;
    PtyWaitForFinishers(PtyExitWaitMs);
    waker.Free;
  end;
end;

procedure KillLeftovers;
var
  o: RawByteString;
begin
  RunPlain('wsl.exe -d Ubuntu -- sh -c "pkill -x sz; pkill -x rz; true"', 15000, o);
end;

{ C:\x\y -> /mnt/c/x/y }
function WslPath(const AWin: string): string;
begin
  Result := '/mnt/' + LowerCase(AWin[1]) + StringReplace(Copy(AWin, 3, MaxInt), '\', '/', [rfReplaceAll]);
end;

function Quote(const S: string): string;
begin
  Result := '''' + StringReplace(S, '''', '''\''''', [rfReplaceAll]) + '''';
end;

procedure TTyTerminalZmodemWslTests.NeedWsl;
var
  o: RawByteString;
  code: Int64;
begin
  if not GChecked then
  begin
    GChecked := True;
    code := RunPlain('wsl.exe -d Ubuntu -- sh -c "command -v sz && command -v rz"', 15000, o);
    if code = -3 then
      GReason := 'wsl.exe did not start: ' + o
    else if code <> 0 then
      GReason := Format('sz / rz not found in WSL Ubuntu (exit %d): %s', [code, o]);
  end;
  if GReason <> '' then
    Ignore('WSL Ubuntu with lrzsz is not available: ' + GReason);
end;

function NewDir(const ATag: string): string;
begin
  Result := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'tyzmwsl-' + ATag + '-' + IntToStr(GetTickCount64);
  ForceDirectories(Result);
end;

procedure RemoveDirAll(const ADir: string);
var
  sr: TSearchRec;
begin
  if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*', faAnyFile, sr) = 0 then
  begin
    repeat
      if (sr.Name <> '.') and (sr.Name <> '..') then
        SysUtils.DeleteFile(IncludeTrailingPathDelimiter(ADir) + sr.Name);
    until FindNext(sr) <> 0;
    SysUtils.FindClose(sr);
  end;
  RemoveDir(ADir);
end;

procedure SaveBytes(const APath: string; const AData: RawByteString);
begin
  with TFileStream.Create(APath, fmCreate) do
  try
    if AData <> '' then
      WriteBuffer(AData[1], Length(AData));
  finally
    Free;
  end;
end;

function LoadBytes(const APath: string): RawByteString;
begin
  Result := '';
  if not FileExists(APath) then
    Exit;
  with TFileStream.Create(APath, fmOpenRead or fmShareDenyWrite) do
  try
    SetLength(Result, Size);
    if Size > 0 then
      ReadBuffer(Result[1], Size);
  finally
    Free;
  end;
end;

function Seeded(ASize, ASeed: Integer): RawByteString;
var
  i: Integer;
  x: Cardinal;
begin
  Result := '';
  SetLength(Result, ASize);
  x := Cardinal(ASeed) * 2654435761 + 1;
  for i := 1 to ASize do
  begin
    x := x xor (x shl 13);
    x := x xor (x shr 17);
    x := x xor (x shl 5);
    Result[i] := AnsiChar(x and 255);
  end;
end;

function EveryByte(ASize: Integer): RawByteString;
var
  i: Integer;
begin
  Result := '';
  SetLength(Result, ASize);
  for i := 1 to ASize do
    Result[i] := AnsiChar((i - 1) and 255);
end;

type
  { one transfer: WSL's sz or rz on the pipe backend, the core and the glue }
  TWslRun = class
  public
    Core: TTyTerminalCore;
    Zm: TZmodemStreamHandler;
    Session: TPtySession;
    Waker: TWaker;
    Dir: string;                         { where downloads go }
    Uploads: TStringList;
    Finished: Boolean;
    Result_: TZmResult;
    Message: string;
    Exited: Boolean;
    ExitCode: Int64;
    FlipIn, FlipOut: Int64;              { 1-based byte to damage once; 0 = none }
    SeenIn, SeenOut: Int64;
    CancelAt: Int64;                     { cancel once this many bytes went; 0 = never }
    Cancelled: Boolean;
    Sent: RawByteString;
    constructor Create(const ADir: string);
    destructor Destroy; override;
    procedure OnData(Sender: TObject; const AData: RawByteString);
    procedure OnDelivered(Sender: TObject; ATag: PtrInt);
    function CanSend: Integer;
    procedure OnDownload(Sender: TObject);
    procedure OnUpload(Sender: TObject);
    procedure OnProgress(Sender: TObject; const AName: string; AFileDone, AFileSize, ATotalDone: Int64);
    procedure OnFinished(Sender: TObject; AResult: TZmResult; const AMessage: string);
    procedure OnClaimed(Sender: TObject; const AData: RawByteString);
    function Run(const ACommand: string; ATimeoutMs: Integer = 60000): Boolean;
    function Screen: string;
  end;

constructor TWslRun.Create(const ADir: string);
begin
  inherited Create;
  Dir := ADir;
  Uploads := TStringList.Create;
  Core := TTyTerminalCore.Create(80, 24);
  Core.OnData := @OnData;
  Core.OnClaimedInput := @OnClaimed;
  Zm := TZmodemStreamHandler.Create(Core);
  Zm.OnDownloadRequest := @OnDownload;
  Zm.OnUploadRequest := @OnUpload;
  Zm.OnProgress := @OnProgress;
  Zm.OnFinished := @OnFinished;
  Zm.CanSend := @CanSend;
  Waker := TWaker.Create;
end;

destructor TWslRun.Destroy;
begin
  Zm.Free;
  Session.Free;
  PtyWaitForFinishers(PtyExitWaitMs);
  Core.Free;
  Waker.Free;
  Uploads.Free;
  inherited Destroy;
end;

procedure TWslRun.OnData(Sender: TObject; const AData: RawByteString);
var
  s: RawByteString;
begin
  s := AData;
  { I10: one of our bytes damaged on the way }
  if (FlipOut > 0) and (SeenOut < FlipOut) and (SeenOut + Length(s) >= FlipOut) then
  begin
    UniqueString(s);
    s[FlipOut - SeenOut] := AnsiChar(Ord(s[FlipOut - SeenOut]) xor $5A);
  end;
  Inc(SeenOut, Length(s));
  if (Session <> nil) and not Session.Closed then
    Session.Write(s);
end;

procedure TWslRun.OnDelivered(Sender: TObject; ATag: PtrInt);
begin
  if (Session <> nil) and not Session.Closed then
    Session.Delivered(ATag);
end;

function TWslRun.CanSend: Integer;
begin
  if (Session = nil) or Session.Closed then
    Exit(0);
  Result := 256 * 1024 - Session.PendingWrite;
end;

procedure TWslRun.OnDownload(Sender: TObject);
begin
  Zm.AcceptDownload(Dir);
end;

procedure TWslRun.OnUpload(Sender: TObject);
begin
  Zm.StartUpload(Uploads);
end;

procedure TWslRun.OnProgress(Sender: TObject; const AName: string; AFileDone, AFileSize, ATotalDone: Int64);
begin
  if (CancelAt > 0) and not Cancelled and (ATotalDone >= CancelAt) then
    Cancelled := True;                   { the cancel runs from the loop, as a click would }
end;

procedure TWslRun.OnFinished(Sender: TObject; AResult: TZmResult; const AMessage: string);
begin
  Finished := True;
  Result_ := AResult;
  Message := AMessage;
end;

procedure TWslRun.OnClaimed(Sender: TObject; const AData: RawByteString);
begin
  Zm.UserInput(AData);
end;

function TWslRun.Run(const ACommand: string; ATimeoutMs: Integer): Boolean;
var
  err: string;
  data: RawByteString;
  ended: Boolean;
  code: Int64;
  t0, lastTick: QWord;
  didCancel: Boolean;
begin
  Session := TPtySession.Create(TProcessPipeBackend.Create(False));
  Session.OnWake := @Waker.Wake;
  if not Session.Start(ACommand, 80, 24, err) then
    raise Exception.Create('not started: ' + err);
  t0 := GetTickCount64;
  lastTick := t0;
  didCancel := False;
  while GetTickCount64 - t0 < QWord(ATimeoutMs) do
  begin
    Waker.Event.WaitFor(20);
    if Session.Pump(data, ended, code) then
    begin
      { I6: one of the program's bytes damaged on the way }
      if (FlipIn > 0) and (SeenIn < FlipIn) and (SeenIn + Length(data) >= FlipIn) then
      begin
        UniqueString(data);
        data[FlipIn - SeenIn] := AnsiChar(Ord(data[FlipIn - SeenIn]) xor $5A);
      end;
      Inc(SeenIn, Length(data));
      if data <> '' then
        Core.Write(data, @OnDelivered, Length(data));
      if ended then
      begin
        Self.Exited := True;
        Self.ExitCode := code;
      end;
    end;
    while Core.ProcessPending do ;
    if Cancelled and not didCancel then
    begin
      didCancel := True;
      Zm.Cancel;
    end;
    if GetTickCount64 - lastTick >= 100 then
    begin
      lastTick := GetTickCount64;
      Zm.Tick(TyTermDefaultClock);
    end;
    if Self.Exited and (Finished or (Zm.State = zsIdle)) then
      Exit(True);
  end;
  Result := False;
end;

function TWslRun.Screen: string;
var
  y: Integer;
begin
  Result := '';
  for y := 0 to Core.Buffer.Lines.Length - 1 do
    Result := Result + Core.Buffer.TranslateBufferLineToString(y, True) + #10;
end;

{ one download: AFiles (name, bytes) written in a Windows folder, sz in WSL sends them,
  the glue saves them into another folder }
procedure Download(ACase: TTestCase; const ATag, ASzOptions: string; const ANames: array of string;
  const AData: array of RawByteString; AFlipIn: Int64 = 0);
var
  src, dst, names: string;
  r: TWslRun;
  i: Integer;
  t0: QWord;
begin
  src := NewDir(ATag + '-src');
  dst := NewDir(ATag + '-dst');
  r := TWslRun.Create(dst);
  try
    names := '';
    for i := 0 to High(ANames) do
    begin
      SaveBytes(src + PathDelim + ANames[i], AData[i]);
      names := names + ' ' + Quote(ANames[i]);
    end;
    r.FlipIn := AFlipIn;
    t0 := GetTickCount64;
    ACase.AssertTrue(ATag + ': ended within 60 s: ' + r.Screen,
      r.Run('wsl.exe -d Ubuntu --cd "' + WslPath(src) + '"' + ' -- sz ' + ASzOptions + names));
    if Length(AData) > 0 then
      WriteLn(Format('%s: %d bytes in %d ms', [ATag, Length(AData[High(AData)]), GetTickCount64 - t0]));
    ACase.AssertTrue(ATag + ': finished', r.Finished);
    ACase.AssertTrue(ATag + ': ok (' + r.Message + ')', r.Result_ = zrOk);
    ACase.AssertEquals(ATag + ': sz exit code', 0, r.ExitCode);
    for i := 0 to High(ANames) do
    begin
      ACase.AssertTrue(Format('%s: %s is there', [ATag, ANames[i]]), FileExists(dst + PathDelim + ANames[i]));
      ACase.AssertTrue(Format('%s: %s byte for byte', [ATag, ANames[i]]),
        LoadBytes(dst + PathDelim + ANames[i]) = AData[i]);
    end;
  finally
    r.Free;
    KillLeftovers;
    RemoveDirAll(src);
    RemoveDirAll(dst);
  end;
end;

procedure TTyTerminalZmodemWslTests.TestDownloadSmallFiles;
begin
  NeedWsl;
  Download(Self, 'i1-0', '', ['zero.bin'], ['']);
  Download(Self, 'i1-1', '', ['one.bin'], ['x']);
  Download(Self, 'i1-1024', '', ['k.bin'], [Seeded(1024, 1)]);
  Download(Self, 'i1-1025', '', ['k1.bin'], [Seeded(1025, 2)]);
end;

procedure TTyTerminalZmodemWslTests.TestDownloadEveryByteValue;
begin
  NeedWsl;
  Download(Self, 'i2', '', ['bytes.bin'], [EveryByte(65536)]);
  Download(Self, 'i2-e', '-e', ['bytes.bin'], [EveryByte(65536)]);
end;

procedure TTyTerminalZmodemWslTests.TestDownloadABigFile;
begin
  NeedWsl;
  Download(Self, 'i3', '', ['big.bin'], [Seeded(1536 * 1024, 3)]);
end;

procedure TTyTerminalZmodemWslTests.TestDownloadThreeAtOnce;
begin
  NeedWsl;
  Download(Self, 'i4', '', ['a.bin', 'b.bin', 'c.bin'], [Seeded(100, 4), Seeded(5000, 5), Seeded(70000, 6)]);
end;

procedure TTyTerminalZmodemWslTests.TestDownloadBigBlocksAndAWindow;
begin
  NeedWsl;
  Download(Self, 'i5-8', '-8', ['b8.bin'], [Seeded(200000, 7)]);
  Download(Self, 'i5-w', '-w 2048', ['bw.bin'], [Seeded(200000, 8)]);
end;

procedure TTyTerminalZmodemWslTests.TestDownloadWithADamagedByte;
begin
  NeedWsl;
  Download(Self, 'i6', '', ['dmg.bin'], [Seeded(100000, 9)], 20000);
end;

{ I7. Mutation: the bytes after the session dropped. }
procedure TTyTerminalZmodemWslTests.TestWhatFollowsTheDownload;
var
  src, dst: string;
  r: TWslRun;
  data: RawByteString;
begin
  NeedWsl;
  src := NewDir('i7-src');
  dst := NewDir('i7-dst');
  r := TWslRun.Create(dst);
  try
    data := Seeded(3000, 10);
    SaveBytes(src + PathDelim + 'f.bin', data);
    AssertTrue('ended: ' + r.Screen, r.Run('wsl.exe -d Ubuntu --cd "' + WslPath(src) + '"'
      + ' -- sh -c ''sz f.bin; printf TAIL-$?'''));
    AssertTrue('ok ' + r.Message, r.Result_ = zrOk);
    AssertTrue('the file', LoadBytes(dst + PathDelim + 'f.bin') = data);
    AssertTrue('what followed is shown: ' + r.Screen, Pos('TAIL-0', r.Screen) > 0);
    AssertTrue('after the summary: ' + r.Screen, Pos('TAIL-0', r.Screen) > Pos('Received 1 file(s)', r.Screen));
  finally
    r.Free;
    KillLeftovers;
    RemoveDirAll(src);
    RemoveDirAll(dst);
  end;
end;

procedure TTyTerminalZmodemWslTests.TestCancellingADownload;
var
  src, dst: string;
  r: TWslRun;
begin
  NeedWsl;
  src := NewDir('i8-src');
  dst := NewDir('i8-dst');
  r := TWslRun.Create(dst);
  try
    SaveBytes(src + PathDelim + 'big.bin', Seeded(1536 * 1024, 11));
    r.CancelAt := 200 * 1024;
    AssertTrue('ended: ' + r.Screen, r.Run('wsl.exe -d Ubuntu --cd "' + WslPath(src) + '"'
      + ' -- sh -c ''sz big.bin; printf "EXIT-$?"'''));
    AssertTrue('cancelled here', r.Result_ = zrCancelledHere);
    AssertTrue('sz said how it ended: ' + r.Screen, Pos('EXIT-', r.Screen) > 0);
    AssertEquals('not a clean exit: ' + r.Screen, 0, Pos('EXIT-0', r.Screen));
    AssertFalse('no half file', FileExists(dst + PathDelim + 'big.bin'));
  finally
    r.Free;
    KillLeftovers;
    RemoveDirAll(src);
    RemoveDirAll(dst);
  end;
end;

{ one upload: the files in a Windows folder, rz in WSL takes them into another }
procedure Upload(ACase: TTestCase; const ATag, ARzOptions: string; const ANames: array of string;
  const AData: array of RawByteString; AFlipOut: Int64 = 0);
var
  src, dst: string;
  r: TWslRun;
  i: Integer;
  t0: QWord;
begin
  src := NewDir(ATag + '-src');
  dst := NewDir(ATag + '-dst');
  r := TWslRun.Create(src);
  try
    for i := 0 to High(ANames) do
    begin
      SaveBytes(src + PathDelim + ANames[i], AData[i]);
      r.Uploads.Add(src + PathDelim + ANames[i]);
    end;
    r.FlipOut := AFlipOut;
    t0 := GetTickCount64;
    ACase.AssertTrue(ATag + ': ended within 60 s: ' + r.Screen,
      r.Run('wsl.exe -d Ubuntu --cd "' + WslPath(dst) + '"' + ' -- rz ' + ARzOptions));
    WriteLn(Format('%s: %d bytes in %d ms', [ATag, Length(AData[High(AData)]), GetTickCount64 - t0]));
    ACase.AssertTrue(ATag + ': ok (' + r.Message + ')', r.Result_ = zrOk);
    ACase.AssertEquals(ATag + ': rz exit code', 0, r.ExitCode);
    for i := 0 to High(ANames) do
    begin
      ACase.AssertTrue(Format('%s: %s is there', [ATag, ANames[i]]), FileExists(dst + PathDelim + ANames[i]));
      ACase.AssertTrue(Format('%s: %s byte for byte', [ATag, ANames[i]]),
        LoadBytes(dst + PathDelim + ANames[i]) = AData[i]);
    end;
  finally
    r.Free;
    KillLeftovers;
    RemoveDirAll(src);
    RemoveDirAll(dst);
  end;
end;

{ I9. Mutation: the sender ignoring ESCCTL (rz -e). }
procedure TTyTerminalZmodemWslTests.TestUploads;
begin
  NeedWsl;
  Upload(Self, 'i9-0', '', ['zero.bin'], ['']);
  Upload(Self, 'i9-bytes', '', ['bytes.bin'], [EveryByte(65536)]);
  Upload(Self, 'i9-big', '', ['big.bin'], [Seeded(1536 * 1024, 12)]);
  Upload(Self, 'i9-two', '', ['one.bin', 'two.bin'], [Seeded(3000, 13), Seeded(40000, 14)]);
  Upload(Self, 'i9-e', '-e', ['esc.bin'], [EveryByte(20000)]);
  Upload(Self, 'i9-name', '', ['a b '#$E4#$B8#$AD#$E6#$96#$87'.bin'], [Seeded(100, 15)]);
end;

procedure TTyTerminalZmodemWslTests.TestUploadWithADamagedByte;
begin
  NeedWsl;
  Upload(Self, 'i10', '', ['dmg.bin'], [Seeded(100000, 16)], 30000);
end;

procedure TTyTerminalZmodemWslTests.TestCancellingAnUpload;
var
  src, dst: string;
  r: TWslRun;
begin
  NeedWsl;
  src := NewDir('i11-src');
  dst := NewDir('i11-dst');
  r := TWslRun.Create(src);
  try
    SaveBytes(src + PathDelim + 'big.bin', Seeded(1536 * 1024, 17));
    r.Uploads.Add(src + PathDelim + 'big.bin');
    r.CancelAt := 200 * 1024;
    AssertTrue('ended: ' + r.Screen, r.Run('wsl.exe -d Ubuntu --cd "' + WslPath(dst) + '"' + ' -- rz'));
    AssertTrue('cancelled here', r.Result_ = zrCancelledHere);
    AssertTrue('rz exited', r.Exited);
    AssertTrue(Format('rz did not end well (%d)', [r.ExitCode]), r.ExitCode <> 0);
  finally
    r.Free;
    KillLeftovers;
    RemoveDirAll(src);
    RemoveDirAll(dst);
  end;
end;

{$ELSE}

procedure TTyTerminalZmodemWslTests.NeedWsl;
begin
  Ignore('WSL Ubuntu with lrzsz is not available: not Windows');
end;

procedure TTyTerminalZmodemWslTests.TestDownloadSmallFiles; begin NeedWsl; end;
procedure TTyTerminalZmodemWslTests.TestDownloadEveryByteValue; begin NeedWsl; end;
procedure TTyTerminalZmodemWslTests.TestDownloadABigFile; begin NeedWsl; end;
procedure TTyTerminalZmodemWslTests.TestDownloadThreeAtOnce; begin NeedWsl; end;
procedure TTyTerminalZmodemWslTests.TestDownloadBigBlocksAndAWindow; begin NeedWsl; end;
procedure TTyTerminalZmodemWslTests.TestDownloadWithADamagedByte; begin NeedWsl; end;
procedure TTyTerminalZmodemWslTests.TestWhatFollowsTheDownload; begin NeedWsl; end;
procedure TTyTerminalZmodemWslTests.TestCancellingADownload; begin NeedWsl; end;
procedure TTyTerminalZmodemWslTests.TestUploads; begin NeedWsl; end;
procedure TTyTerminalZmodemWslTests.TestUploadWithADamagedByte; begin NeedWsl; end;
procedure TTyTerminalZmodemWslTests.TestCancellingAnUpload; begin NeedWsl; end;

{$ENDIF}

initialization
  RegisterTest(TTyTerminalZmodemWslTests);
end.
