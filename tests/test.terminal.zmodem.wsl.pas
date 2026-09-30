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
  same kind of transfers through the Unix PTY backend.

  P1-P5 (7 期验收反馈): the example's pipe-mode WSL entry (umain's PipeWslCommand) on the
  example's pipe backend (uwslresize's TWslPipeBackend) -- script opens a PTY in Linux, so
  the shell on the pipe is an interactive one with a line discipline -- sz / rz typed
  into it, the prompt clean afterwards, and a size change that gets there through the side
  process (also in the middle of a download). They also need script (util-linux) in
  Ubuntu. }

interface

uses
  Classes, SysUtils, fpcunit, testregistry;

type
  TTyTerminalZmodemWslTests = class(TTestCase)
  private
    procedure NeedWsl;
    procedure NeedWslScript;
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
    procedure TestThePipeShellHasATerminal;                  { P1 }
    procedure TestSzInThePipeShell;                          { P2 }
    procedure TestRzInThePipeShell;                          { P3 }
    procedure TestAResizeReachesThePipeShell;                { P4 }
    procedure TestAResizeDuringADownload;                    { P5 }
  end;

implementation

{$IFDEF MSWINDOWS}
uses
  Windows, SyncObjs, Math, md5, tyControls.Terminal.Buffer, tyControls.Terminal.Core,
  uptysession, uptywin, uzmodem, uzmodemsession, uzmodemterm, umain, uwslresize;

const
  { I6 / I10: about 1 s when the ZRPOS puts the damage right; a recovery only by the
    10 s timeout of either side takes longer than this }
  DamagedWithinMs = 7000;

var
  GChecked: Boolean = False;
  GReason: string = '';
  GScriptChecked: Boolean = False;
  GScriptReason: string = '';

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

procedure TTyTerminalZmodemWslTests.NeedWslScript;
var
  o: RawByteString;
  code: Int64;
begin
  NeedWsl;
  if not GScriptChecked then
  begin
    GScriptChecked := True;
    code := RunPlain('wsl.exe -d Ubuntu -- sh -c "command -v script"', 15000, o);
    if code <> 0 then
      GScriptReason := Format('script not found in WSL Ubuntu (exit %d): %s', [code, o]);
  end;
  if GScriptReason <> '' then
    Ignore('script (util-linux) is not available: ' + GScriptReason);
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
  TWslCond = function: Boolean is nested;

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
    AllIn, AllOut: RawByteString;        { the first bytes each way, for a failure message }
    { what the program sent -- of a batch that comes while a transfer runs only its last
      4 KB (a download's megabytes appended would cost seconds; the prompt after it is at
      a batch's end) }
    Raw: RawByteString;
    MergeStderr: Boolean;                { the pipe backend as the example makes it }
    WslBackend: Boolean;                 { the example's pipe backend (TWslPipeBackend) }
    Backend: TProcessPipeBackend;        { the session's, while it runs }
    FLastTick: QWord;
    FDidCancel: Boolean;
    constructor Create(const ADir: string; ACols: Integer = 80; ARows: Integer = 24);
    destructor Destroy; override;
    procedure OnData(Sender: TObject; const AData: RawByteString);
    procedure OnDelivered(Sender: TObject; ATag: PtrInt);
    function CanSend: Integer;
    procedure OnDownload(Sender: TObject);
    procedure OnUpload(Sender: TObject);
    procedure OnProgress(Sender: TObject; const AName: string; AFileDone, AFileSize, ATotalDone: Int64);
    procedure OnFinished(Sender: TObject; AResult: TZmResult; const AMessage: string);
    procedure OnClaimed(Sender: TObject; const AData: RawByteString);
    procedure Start(const ACommand: string);
    { one turn of the example's loop: the program's output into the core, a cancel, the tick }
    procedure Step;
    function Run(const ACommand: string; ATimeoutMs: Integer = 60000): Boolean;
    function WaitUntil(ACond: TWslCond; ATimeoutMs: Integer): Boolean;
    { keys typed into the program }
    procedure Send(const AKeys: RawByteString);
    function Screen: string;
    { how it ended, for a failure message }
    function Describe: string;
  end;

constructor TWslRun.Create(const ADir: string; ACols: Integer; ARows: Integer);
begin
  inherited Create;
  Dir := ADir;
  Uploads := TStringList.Create;
  Core := TTyTerminalCore.Create(ACols, ARows);
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
  if Length(AllOut) < 600 then
    AllOut := AllOut + Copy(s, 1, 600 - Length(AllOut));
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

procedure TWslRun.Start(const ACommand: string);
var
  err: string;
begin
  if WslBackend then
    Backend := TWslPipeBackend.Create(MergeStderr)
  else
    Backend := TProcessPipeBackend.Create(MergeStderr);
  Session := TPtySession.Create(Backend);
  Session.OnWake := @Waker.Wake;
  if not Session.Start(ACommand, Core.Cols, Core.Rows, err) then
    raise Exception.Create('not started: ' + err);
  FLastTick := GetTickCount64;
  FDidCancel := False;
end;

procedure TWslRun.Step;
var
  data: RawByteString;
  ended: Boolean;
  code: Int64;
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
    if Length(AllIn) < 600 then
      AllIn := AllIn + Copy(data, 1, 600 - Length(AllIn));
    if (Zm.State <> zsIdle) and (Length(data) > 4096) then
      Raw := Raw + Copy(data, Length(data) - 4095, 4096)
    else
      Raw := Raw + data;
    if data <> '' then
      Core.Write(data, @OnDelivered, Length(data));
    if ended then
    begin
      Self.Exited := True;
      Self.ExitCode := code;
    end;
  end;
  while Core.ProcessPending do ;
  if Cancelled and not FDidCancel then
  begin
    FDidCancel := True;
    Zm.Cancel;
  end;
  if GetTickCount64 - FLastTick >= 100 then
  begin
    FLastTick := GetTickCount64;
    Zm.Tick(TyTermDefaultClock);
  end;
end;

function TWslRun.Run(const ACommand: string; ATimeoutMs: Integer): Boolean;
var
  t0: QWord;
begin
  Start(ACommand);
  t0 := GetTickCount64;
  while GetTickCount64 - t0 < QWord(ATimeoutMs) do
  begin
    Step;
    if Self.Exited and (Finished or (Zm.State = zsIdle)) then
      Exit(True);
  end;
  Result := False;
end;

function TWslRun.WaitUntil(ACond: TWslCond; ATimeoutMs: Integer): Boolean;
var
  t0: QWord;
begin
  t0 := GetTickCount64;
  repeat
    Step;
    if ACond() then
      Exit(True);
  until GetTickCount64 - t0 >= QWord(ATimeoutMs);
  Result := False;
end;

procedure TWslRun.Send(const AKeys: RawByteString);
begin
  Session.Write(AKeys);
end;

function HexOf(const S: RawByteString): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do
    if S[i] in [#32..#126] then
      Result := Result + S[i]
    else
      Result := Result + '<' + IntToHex(Ord(S[i]), 2) + '>';
end;

function TWslRun.Describe: string;
begin
  Result := Format('exited %s (code %d), finished %s (%s), state %d, %d bytes in, %d out'#10'in:  %s'#10'out: %s'#10'screen:'#10'%s',
    [BoolToStr(Exited, True), ExitCode, BoolToStr(Finished, True), Message, Ord(Zm.State), SeenIn, SeenOut,
     HexOf(AllIn), HexOf(AllOut), Screen]);
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
{ AWithinMs > 0: the whole transfer takes less (a damaged byte put right by the ZRPOS
  at once, not by the 10 s timeout, which also gets there) }
procedure Download(ACase: TTestCase; const ATag, ASzOptions: string; const ANames: array of string;
  const AData: array of RawByteString; AFlipIn: Int64 = 0; AWithinMs: Integer = 0);
var
  src, dst, names: string;
  r: TWslRun;
  i: Integer;
  t0: QWord;
  ok: Boolean;
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
    ok := r.Run('wsl.exe -d Ubuntu --cd "' + WslPath(src) + '"' + ' -- sz ' + ASzOptions + names);
    t0 := GetTickCount64 - t0;
    ACase.AssertTrue(ATag + ': ended within 60 s: ' + r.Describe, ok);
    if Length(AData) > 0 then
      WriteLn(Format('%s: %d bytes in %d ms', [ATag, Length(AData[High(AData)]), t0]));
    if AWithinMs > 0 then
      ACase.AssertTrue(Format('%s: %d ms, not within %d', [ATag, t0, AWithinMs]), t0 < QWord(AWithinMs));
    ACase.AssertTrue(ATag + ': finished', r.Finished);
    ACase.AssertTrue(ATag + ': ok: ' + r.Describe, r.Result_ = zrOk);
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
  Download(Self, 'i6', '', ['dmg.bin'], [Seeded(100000, 9)], 20000, DamagedWithinMs);
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
  const AData: array of RawByteString; AFlipOut: Int64 = 0; AWithinMs: Integer = 0);
var
  src, dst: string;
  r: TWslRun;
  i: Integer;
  t0: QWord;
  ok: Boolean;
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
    ok := r.Run('wsl.exe -d Ubuntu --cd "' + WslPath(dst) + '"' + ' -- rz ' + ARzOptions);
    t0 := GetTickCount64 - t0;
    ACase.AssertTrue(ATag + ': ended within 60 s: ' + r.Describe, ok);
    WriteLn(Format('%s: %d bytes in %d ms', [ATag, Length(AData[High(AData)]), t0]));
    if AWithinMs > 0 then
      ACase.AssertTrue(Format('%s: %d ms, not within %d', [ATag, t0, AWithinMs]), t0 < QWord(AWithinMs));
    ACase.AssertTrue(ATag + ': ok: ' + r.Describe, r.Result_ = zrOk);
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
  Upload(Self, 'i10', '', ['dmg.bin'], [Seeded(100000, 16)], 30000, DamagedWithinMs);
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

{ ---- P1-P3: the pipe mode's WSL entry ------------------------------------------------ }

const
  { the prompt the cases set (the user's own may be anything) }
  TestPrompt = 'TY> ';

{ the example's pipe-mode WSL entry, in Ubuntu (what NeedWsl checked), started in ADir,
  for the grid ACols x ARows }
function PipeShellCommand(const ADir: string; ACols, ARows: Integer): string;
const
  Head = 'wsl.exe -e ';
begin
  if Copy(PipeWslCommand, 1, Length(Head)) <> Head then
    raise Exception.Create('the example''s WSL entry no longer starts with "' + Head + '": ' + PipeWslCommand);
  Result := ExpandGridSize('wsl.exe -d Ubuntu --cd "' + WslPath(ADir) + '" -e '
    + Copy(PipeWslCommand, Length(Head) + 1, MaxInt), ACols, ARows);
end;

function EndsWith(const S, ATail: RawByteString): Boolean;
begin
  Result := (Length(S) >= Length(ATail)) and (Copy(S, Length(S) - Length(ATail) + 1, Length(ATail)) = ATail);
end;

{ the last line of the screen with something on it }
function LastLine(const AScreen: string): string;
var
  sl: TStringList;
  i: Integer;
begin
  Result := '';
  sl := TStringList.Create;
  try
    sl.Text := AScreen;
    for i := sl.Count - 1 downto 0 do
      if Trim(sl[i]) <> '' then
        Exit(TrimRight(sl[i]));
  finally
    sl.Free;
  end;
end;

{ the loop runs AMs longer: whatever was still on the way arrives }
procedure Settle(R: TWslRun; AMs: Integer);
var
  t0: QWord;
begin
  t0 := GetTickCount64;
  while GetTickCount64 - t0 < QWord(AMs) do
    R.Step;
end;

{ the shell's own first prompt (whatever it is: the output stops for a while), then
  TestPrompt for the rest of the case }
procedure StartPipeShell(ACase: TTestCase; R: TWslRun; const ADir: string);
var
  n: Integer;
  t: QWord;

  function Some: Boolean;
  begin
    Result := R.Raw <> '';
  end;

  function Quiet: Boolean;
  begin
    if Length(R.Raw) <> n then
    begin
      n := Length(R.Raw);
      t := GetTickCount64;
    end;
    Result := GetTickCount64 - t >= 800;
  end;

  function Prompted: Boolean;
  begin
    Result := EndsWith(R.Raw, TestPrompt);
  end;

begin
  R.MergeStderr := True;
  R.WslBackend := True;
  R.Start(PipeShellCommand(ADir, R.Core.Cols, R.Core.Rows));
  ACase.AssertTrue('the shell said something: ' + R.Describe, R.WaitUntil(@Some, 20000));
  n := -1;
  t := GetTickCount64;
  ACase.AssertTrue('and then waited: ' + R.Describe, R.WaitUntil(@Quiet, 20000));
  R.Send('PS1=''' + TestPrompt + '''' + #13);
  ACase.AssertTrue('the prompt set: ' + HexOf(R.Raw), R.WaitUntil(@Prompted, 10000));
end;

{ a line typed and Enter (a CR, as the terminal sends it); what came until the prompt was back }
function RunLine(ACase: TTestCase; R: TWslRun; const ALine: string; ATimeoutMs: Integer = 15000): RawByteString;
var
  mark: Integer;

  function Back: Boolean;
  begin
    Result := (Length(R.Raw) > mark) and EndsWith(R.Raw, TestPrompt);
  end;

begin
  mark := Length(R.Raw);
  R.Send(ALine + #13);
  ACase.AssertTrue('the prompt came back after ' + ALine + ': ' + HexOf(Copy(R.Raw, mark + 1, MaxInt)),
    R.WaitUntil(@Back, ATimeoutMs));
  Result := Copy(R.Raw, mark + 1, MaxInt);
end;

procedure LeavePipeShell(ACase: TTestCase; R: TWslRun);

  function Gone: Boolean;
  begin
    Result := R.Exited;
  end;

begin
  R.Send('exit'#13);
  ACase.AssertTrue('exit ends the shell, script and wsl.exe: ' + R.Describe, R.WaitUntil(@Gone, 15000));
end;

{ P1. Mutations: the entry without script (bash on a pipe is not interactive: no prompt);
  without the stty (tput answers 80 x 24). }
procedure TTyTerminalZmodemWslTests.TestThePipeShellHasATerminal;
var
  dir: string;
  r: TWslRun;
  got: RawByteString;
  i: Integer;
begin
  NeedWslScript;
  dir := NewDir('p1');
  r := TWslRun.Create(dir, 97, 31);
  try
    StartPipeShell(Self, r, dir);
    { h""i: the echo of the line is not the output }
    got := RunLine(Self, r, 'echo h""i');
    AssertTrue('the line is echoed, its Enter as CR LF: ' + HexOf(got), Pos('echo h""i'#13#10, got) > 0);
    AssertTrue('the output, its LF as CR LF: ' + HexOf(got), Pos('hi'#13#10, got) > 0);
    for i := 1 to Length(got) do
      if (got[i] = #10) and ((i = 1) or (got[i - 1] <> #13)) then
        Fail(Format('a bare LF at %d: %s', [i, HexOf(got)]));
    AssertTrue('on the screen: ' + r.Screen, Pos(#10'hi'#10, #10 + r.Screen) > 0);
    got := RunLine(Self, r, 'tput cols; tput lines');
    AssertTrue('the grid stty set: ' + HexOf(got), Pos('97'#13#10'31'#13#10, got) > 0);
    LeavePipeShell(Self, r);
  finally
    r.Free;
    RemoveDirAll(dir);
  end;
end;

{ P2. sz typed into the pipe shell: sz sets the PTY raw, ZMODEM's bytes pass as they are
  (every byte value), the file arrives byte for byte, and afterwards the prompt is back
  clean -- nothing of the protocol on the screen after it, nothing in the shell's input
  (a stray "OO" there would make the next line "OOecho ...: command not found"). }
procedure TTyTerminalZmodemWslTests.TestSzInThePipeShell;
var
  src, dst: string;
  r: TWslRun;
  data, got: RawByteString;
  mark: Integer;

  function Done: Boolean;
  begin
    Result := r.Finished and (r.Zm.State = zsIdle) and (Length(r.Raw) > mark) and EndsWith(r.Raw, TestPrompt);
  end;

begin
  NeedWslScript;
  src := NewDir('p2-src');
  dst := NewDir('p2-dst');
  r := TWslRun.Create(dst);
  try
    data := EveryByte(65536) + Seeded(100000, 20);
    SaveBytes(src + PathDelim + 'every.bin', data);
    StartPipeShell(Self, r, src);
    mark := Length(r.Raw);
    r.Send('sz every.bin'#13);
    AssertTrue('the transfer ended and the prompt came back: ' + r.Describe, r.WaitUntil(@Done, 60000));
    AssertTrue('ok: ' + r.Describe, r.Result_ = zrOk);
    AssertTrue('the file, byte for byte', LoadBytes(dst + PathDelim + 'every.bin') = data);
    Settle(r, 700);
    AssertEquals('the prompt alone on the last line: ' + r.Screen + HexOf(Copy(r.Raw, Length(r.Raw) - 300, MaxInt)),
      TrimRight(TestPrompt), LastLine(r.Screen));
    got := RunLine(Self, r, 'echo "done-$?"');
    AssertTrue('sz ended well, the line reached the shell as typed: ' + HexOf(got), Pos('done-0'#13#10, got) > 0);
    LeavePipeShell(Self, r);
  finally
    r.Free;
    KillLeftovers;
    RemoveDirAll(src);
    RemoveDirAll(dst);
  end;
end;

{ P3. rz typed into the pipe shell: the upload's bytes (every value, ^C ^Z ^D among them)
  reach rz through the PTY as they are -- cmp in WSL says so -- and the prompt is back
  clean. }
procedure TTyTerminalZmodemWslTests.TestRzInThePipeShell;
var
  src, dst: string;
  r: TWslRun;
  data, got: RawByteString;
  mark: Integer;

  function Done: Boolean;
  begin
    Result := r.Finished and (r.Zm.State = zsIdle) and (Length(r.Raw) > mark) and EndsWith(r.Raw, TestPrompt);
  end;

begin
  NeedWslScript;
  src := NewDir('p3-src');
  dst := NewDir('p3-dst');
  r := TWslRun.Create(src);
  try
    data := EveryByte(65536) + Seeded(100000, 21);
    SaveBytes(src + PathDelim + 'up.bin', data);
    r.Uploads.Add(src + PathDelim + 'up.bin');
    StartPipeShell(Self, r, dst);
    mark := Length(r.Raw);
    r.Send('rz'#13);
    AssertTrue('the transfer ended and the prompt came back: ' + r.Describe, r.WaitUntil(@Done, 60000));
    AssertTrue('ok: ' + r.Describe, r.Result_ = zrOk);
    AssertTrue('the file, byte for byte', LoadBytes(dst + PathDelim + 'up.bin') = data);
    Settle(r, 700);
    AssertEquals('the prompt alone on the last line: ' + r.Screen + HexOf(Copy(r.Raw, Length(r.Raw) - 300, MaxInt)),
      TrimRight(TestPrompt), LastLine(r.Screen));
    got := RunLine(Self, r, 'cmp up.bin ' + Quote(WslPath(src) + '/up.bin') + ' && echo "same-$?"');
    AssertTrue('the same bytes in WSL, the line reached the shell as typed: ' + HexOf(got),
      Pos('same-0'#13#10, got) > 0);
    LeavePipeShell(Self, r);
  finally
    r.Free;
    KillLeftovers;
    RemoveDirAll(src);
    RemoveDirAll(dst);
  end;
end;

{ P4. A size change reaches the pipe shell through the side process: a program waiting in
  the foreground gets SIGWINCH, tput answers the new size. The file the wrapper wrote (the
  shell's PID, its PTY) is there while the shell runs and removed after the session.
  Mutations: Resize doing nothing; the cleanup not started. }
procedure TTyTerminalZmodemWslTests.TestAResizeReachesThePipeShell;
var
  dir, f: string;
  r: TWslRun;
  got, o: RawByteString;
  mark: Integer;
  t0: QWord;
  gone: Boolean;

  function Winched: Boolean;
  begin
    Result := Pos('WINCH 77x20', Copy(r.Raw, mark + 1, MaxInt)) > 0;
  end;

  function Prompted: Boolean;
  begin
    Result := Winched and EndsWith(r.Raw, TestPrompt);
  end;

  function SideEnded: Boolean;
  begin
    Result := (r.Backend as TWslPipeBackend).ResizesSent + (r.Backend as TWslPipeBackend).ResizesFailed > 0;
  end;

begin
  NeedWslScript;
  dir := NewDir('p4');
  r := TWslRun.Create(dir, 97, 31);
  f := '';
  try
    StartPipeShell(Self, r, dir);
    f := (r.Backend as TWslPipeBackend).TtyFile;
    AssertEquals('the file: ' + f, 1, Pos('/tmp/tyterm-', f));
    AssertEquals('the wrapper wrote it: the shell''s PID and its PTY', 0,
      RunPlain('wsl.exe -d Ubuntu -- sh -c "read p t < ' + f + ' && test -e /proc/$p && test -c $t"', 15000, o));
    { the trap reports what the kernel's SIGWINCH says; wait returns after it }
    mark := Length(r.Raw);
    r.Send('trap ''echo WINCH $(tput cols)x$(tput lines)'' WINCH; sleep 30 & wait'#13);
    Settle(r, 500);
    t0 := GetTickCount64;
    r.Session.Resize(77, 20);
    AssertTrue('the waiting shell got SIGWINCH: ' + HexOf(Copy(r.Raw, mark + 1, MaxInt)), r.WaitUntil(@Prompted, 10000));
    WriteLn(Format('p4: the new size was there after %d ms', [GetTickCount64 - t0]));
    RunLine(Self, r, 'kill %1; wait');
    got := RunLine(Self, r, 'tput cols; tput lines');
    AssertTrue('tput: ' + HexOf(got), Pos('77'#13#10'20'#13#10, got) > 0);
    { the side process ends a little after its stty }
    AssertTrue('the side process ended', r.WaitUntil(@SideEnded, 5000));
    AssertEquals('one side process', 1, (r.Backend as TWslPipeBackend).ResizesSent);
    AssertEquals('none failed', 0, (r.Backend as TWslPipeBackend).ResizesFailed);
    LeavePipeShell(Self, r);
  finally
    r.Free;
    RemoveDirAll(dir);
  end;
  { the finisher started the removal; it takes a WSL start }
  gone := False;
  t0 := GetTickCount64;
  repeat
    gone := RunPlain('wsl.exe -d Ubuntu -- test -e ' + f, 15000, o) = 1;
    if not gone then Sleep(200);
  until gone or (GetTickCount64 - t0 > 10000);
  AssertTrue('the file is removed after the session: ' + f, gone);
end;

{ P5. A size change in the middle of a download: the side process sets the PTY's size
  while sz sends (sz gets SIGWINCH and goes on), the file arrives byte for byte, and the
  shell has the new size afterwards. }
procedure TTyTerminalZmodemWslTests.TestAResizeDuringADownload;
var
  src, dst: string;
  r: TWslRun;
  data, got: RawByteString;
  mark: Integer;
  base: Int64;
  resized: Boolean;
  sentAtEnd: Integer;
  tStart, tResize, tSent, tEnd: QWord;

  function Done: Boolean;
  begin
    if not resized and (r.Zm.State <> zsIdle) and (r.SeenIn > base + 200 * 1024) then
    begin
      resized := True;
      tResize := GetTickCount64;
      r.Session.Resize(88, 22);
    end;
    if resized and (tSent = 0) and ((r.Backend as TWslPipeBackend).ResizesSent > 0) then
      tSent := GetTickCount64;
    if r.Finished and (sentAtEnd < 0) then
    begin
      tEnd := GetTickCount64;
      sentAtEnd := (r.Backend as TWslPipeBackend).ResizesSent;
    end;
    Result := r.Finished and (r.Zm.State = zsIdle) and (Length(r.Raw) > mark) and EndsWith(r.Raw, TestPrompt);
  end;

begin
  NeedWslScript;
  src := NewDir('p5-src');
  dst := NewDir('p5-dst');
  r := TWslRun.Create(dst);
  try
    data := Seeded(64 * 1024 * 1024, 22);
    SaveBytes(src + PathDelim + 'big.bin', data);
    StartPipeShell(Self, r, src);
    mark := Length(r.Raw);
    base := r.SeenIn;
    resized := False;
    sentAtEnd := -1;
    tResize := 0;
    tSent := 0;
    tEnd := 0;
    tStart := GetTickCount64;
    r.Send('sz big.bin'#13);
    AssertTrue('the transfer ended and the prompt came back: ' + r.Describe, r.WaitUntil(@Done, 120000));
    WriteLn(Format('p5: resize at %d ms, set at %d ms, the transfer ended at %d ms (%d failed)',
      [tResize - tStart, tSent - tStart, tEnd - tStart, (r.Backend as TWslPipeBackend).ResizesFailed]));
    AssertTrue('the size changed in the middle', resized);
    AssertTrue('ok: ' + r.Describe, r.Result_ = zrOk);
    AssertTrue('the file, byte for byte', LoadBytes(dst + PathDelim + 'big.bin') = data);
    AssertEquals('the side process had set the size before the transfer ended', 1, sentAtEnd);
    got := RunLine(Self, r, 'tput cols; tput lines');
    AssertTrue('tput: ' + HexOf(got), Pos('88'#13#10'22'#13#10, got) > 0);
    LeavePipeShell(Self, r);
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
procedure TTyTerminalZmodemWslTests.NeedWslScript; begin NeedWsl; end;
procedure TTyTerminalZmodemWslTests.TestThePipeShellHasATerminal; begin NeedWsl; end;
procedure TTyTerminalZmodemWslTests.TestSzInThePipeShell; begin NeedWsl; end;
procedure TTyTerminalZmodemWslTests.TestRzInThePipeShell; begin NeedWsl; end;
procedure TTyTerminalZmodemWslTests.TestAResizeReachesThePipeShell; begin NeedWsl; end;
procedure TTyTerminalZmodemWslTests.TestAResizeDuringADownload; begin NeedWsl; end;

{$ENDIF}

initialization
  RegisterTest(TTyTerminalZmodemWslTests);
end.
