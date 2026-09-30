program zmwsl;

{ The terminal example's ZMODEM against lrzsz through a real Unix PTY (phase 7, spec
  19.9): the Linux path of the WSL tests (tests/test.terminal.zmodem.wsl, which go
  through Windows pipes). The core, the stream hook, the glue (uzmodemterm) and the
  Unix PTY backend (uptyunix) are the example's own; no LCL. Built and run in WSL:

    cd tools/terminal-zmodem-wsl && mkdir -p lib && \
      fpc -Mobjfpc -Sh -FUlib -Fu../../examples/terminal -Fu../../source zmwsl.lpr && ./zmwsl

  Downloads (sz in the PTY: it sets the terminal raw itself) and uploads (rz), each
  compared byte for byte. Prints PASS / FAIL per case and, last,
  "zmwsl: N passed, M failed"; the exit code is M. }

{$mode objfpc}{$H+}

uses
  cthreads, Classes, SysUtils, SyncObjs, BaseUnix, Unix, tyControls.Terminal.Core, uptysession, uptyunix,
  uzmodem, uzmodemsession, uzmodemterm;

type
  TWaker = class
  public
    Event: TEvent;
    constructor Create;
    destructor Destroy; override;
    procedure Wake(Sender: TObject);
  end;

  TRun = class
  public
    Core: TTyTerminalCore;
    Zm: TZmodemStreamHandler;
    Session: TPtySession;
    Waker: TWaker;
    Dir: string;
    Uploads: TStringList;
    Finished, Exited: Boolean;
    Result_: TZmResult;
    Message: string;
    Code: Int64;
    constructor Create(const ADir: string);
    destructor Destroy; override;
    procedure OnData(Sender: TObject; const AData: RawByteString);
    procedure OnDelivered(Sender: TObject; ATag: PtrInt);
    function CanSend: Integer;
    procedure OnDownload(Sender: TObject);
    procedure OnUpload(Sender: TObject);
    procedure OnFinished(Sender: TObject; AResult: TZmResult; const AMessage: string);
    function Run(const ACommand: string): Boolean;
    function Screen: string;
  end;

var
  Passed, Failed: Integer;
  Base: string;

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

constructor TRun.Create(const ADir: string);
begin
  inherited Create;
  Dir := ADir;
  Uploads := TStringList.Create;
  Core := TTyTerminalCore.Create(80, 24);
  Core.OnData := @OnData;
  Zm := TZmodemStreamHandler.Create(Core);
  Zm.OnDownloadRequest := @OnDownload;
  Zm.OnUploadRequest := @OnUpload;
  Zm.OnFinished := @OnFinished;
  Zm.CanSend := @CanSend;
  Waker := TWaker.Create;
end;

destructor TRun.Destroy;
begin
  Zm.Free;
  Session.Free;
  PtyWaitForFinishers(PtyExitWaitMs);
  Core.Free;
  Waker.Free;
  Uploads.Free;
  inherited Destroy;
end;

procedure TRun.OnData(Sender: TObject; const AData: RawByteString);
begin
  if (Session <> nil) and not Session.Closed then
    Session.Write(AData);
end;

procedure TRun.OnDelivered(Sender: TObject; ATag: PtrInt);
begin
  if (Session <> nil) and not Session.Closed then
    Session.Delivered(ATag);
end;

function TRun.CanSend: Integer;
begin
  if (Session = nil) or Session.Closed then
    Exit(0);
  Result := 256 * 1024 - Session.PendingWrite;
end;

procedure TRun.OnDownload(Sender: TObject);
begin
  Zm.AcceptDownload(Dir);
end;

procedure TRun.OnUpload(Sender: TObject);
begin
  Zm.StartUpload(Uploads);
end;

procedure TRun.OnFinished(Sender: TObject; AResult: TZmResult; const AMessage: string);
begin
  Finished := True;
  Result_ := AResult;
  Message := AMessage;
end;

function TRun.Run(const ACommand: string): Boolean;
var
  err: string;
  data: RawByteString;
  ex: Boolean;
  c: Int64;
  t0, lastTick: QWord;
begin
  Session := TPtySession.Create(TUnixPtyBackend.Create);
  Session.OnWake := @Waker.Wake;
  if not Session.Start(ACommand, 80, 24, err) then
  begin
    Message := 'not started: ' + err;
    Exit(False);
  end;
  t0 := GetTickCount64;
  lastTick := t0;
  while GetTickCount64 - t0 < 60000 do
  begin
    Waker.Event.WaitFor(20);
    if Session.Pump(data, ex, c) then
    begin
      if data <> '' then
        Core.Write(data, @OnDelivered, Length(data));
      if ex then
      begin
        Exited := True;
        Code := c;
      end;
    end;
    while Core.ProcessPending do ;
    if GetTickCount64 - lastTick >= 100 then
    begin
      lastTick := GetTickCount64;
      Zm.Tick(TyTermDefaultClock);
    end;
    if Exited and (Finished or (Zm.State = zsIdle)) then
      Exit(True);
  end;
  Result := False;
end;

function TRun.Screen: string;
var
  y: Integer;
begin
  Result := '';
  for y := 0 to Core.Buffer.Lines.Length - 1 do
    Result := Result + Core.Buffer.TranslateBufferLineToString(y, True) + #10;
end;

procedure Pass(const AName: string);
begin
  Inc(Passed);
  WriteLn('PASS ', AName);
end;

procedure Fail(const AName, AWhy: string);
begin
  Inc(Failed);
  WriteLn('FAIL ', AName, ': ', AWhy);
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

function LoadBytes(const APath: string; out AData: RawByteString): Boolean;
begin
  AData := '';
  Result := FileExists(APath);
  if not Result then
    Exit;
  with TFileStream.Create(APath, fmOpenRead) do
  try
    SetLength(AData, Size);
    if Size > 0 then
      ReadBuffer(AData[1], Size);
  finally
    Free;
  end;
end;

function Quote(const S: string): string;
begin
  Result := '''' + StringReplace(S, '''', '''\''''', [rfReplaceAll]) + '''';
end;

function NewDir(const ATag: string): string;
begin
  Result := Base + '/' + ATag;
  ForceDirectories(Result);
end;

procedure CheckFiles(const AName, ADir: string; const ANames: array of string;
  const AData: array of RawByteString; r: TRun; AMs: QWord);
var
  i: Integer;
  got: RawByteString;
begin
  if not r.Finished then begin Fail(AName, 'not finished: ' + r.Message + #10 + r.Screen); Exit; end;
  if r.Result_ <> zrOk then begin Fail(AName, 'result ' + r.Message); Exit; end;
  if r.Code <> 0 then begin Fail(AName, 'exit code ' + IntToStr(r.Code)); Exit; end;
  for i := 0 to High(ANames) do
    if not LoadBytes(ADir + '/' + ANames[i], got) then
    begin
      Fail(AName, ANames[i] + ' missing');
      Exit;
    end
    else if got <> AData[i] then
    begin
      Fail(AName, Format('%s differs (%d bytes, %d sent)', [ANames[i], Length(got), Length(AData[i])]));
      Exit;
    end;
  Pass(Format('%s (%d ms)', [AName, AMs]));
end;

procedure Download(const AName, AOptions: string; const ANames: array of string;
  const AData: array of RawByteString; const ATail: string = '');
var
  src, dst, names: string;
  r: TRun;
  i: Integer;
  t0: QWord;
begin
  src := NewDir(AName + '-src');
  dst := NewDir(AName + '-dst');
  names := '';
  for i := 0 to High(ANames) do
  begin
    SaveBytes(src + '/' + ANames[i], AData[i]);
    names := names + ' ' + Quote(ANames[i]);
  end;
  r := TRun.Create(dst);
  try
    t0 := GetTickCount64;
    if not r.Run('cd ' + Quote(src) + ' && sz ' + AOptions + names + ATail) then
      Fail(AName, 'did not end: ' + r.Message + #10 + r.Screen)
    else if (ATail <> '') and (Pos('TAIL-0', r.Screen) = 0) then
      Fail(AName, 'what followed is missing:'#10 + r.Screen)
    else
      CheckFiles(AName, dst, ANames, AData, r, GetTickCount64 - t0);
  finally
    r.Free;
  end;
end;

procedure Upload(const AName, AOptions: string; const ANames: array of string;
  const AData: array of RawByteString);
var
  src, dst: string;
  r: TRun;
  i: Integer;
  t0: QWord;
begin
  src := NewDir(AName + '-src');
  dst := NewDir(AName + '-dst');
  r := TRun.Create(src);
  try
    for i := 0 to High(ANames) do
    begin
      SaveBytes(src + '/' + ANames[i], AData[i]);
      r.Uploads.Add(src + '/' + ANames[i]);
    end;
    t0 := GetTickCount64;
    if not r.Run('cd ' + Quote(dst) + ' && rz ' + AOptions) then
      Fail(AName, 'did not end: ' + r.Message + #10 + r.Screen)
    else
      CheckFiles(AName, dst, ANames, AData, r, GetTickCount64 - t0);
  finally
    r.Free;
  end;
end;

begin
  Base := '/tmp/zmwsl-' + IntToStr(FpGetpid);
  ForceDirectories(Base);
  { I1 }
  Download('I1 download 0 1 1024 1025', '', ['zero.bin', 'one.bin', 'k.bin', 'k1.bin'],
    ['', 'x', Seeded(1024, 1), Seeded(1025, 2)]);
  { I2 }
  Download('I2 download every byte value', '', ['bytes.bin'], [EveryByte(65536)]);
  Download('I2 download every byte value, sz -e', '-e', ['bytes.bin'], [EveryByte(65536)]);
  { I3 }
  Download('I3 download 1.5 MB', '', ['big.bin'], [Seeded(1536 * 1024, 3)]);
  { I4 }
  Download('I4 download three at once', '', ['a.bin', 'b.bin', 'c.bin'],
    [Seeded(100, 4), Seeded(5000, 5), Seeded(70000, 6)]);
  { I7 }
  Download('I7 what follows the download', '', ['f.bin'], [Seeded(3000, 10)], '; printf TAIL-$?');
  { I9 }
  Upload('I9 upload every byte value', '', ['bytes.bin'], [EveryByte(65536)]);
  Upload('I9 upload 1.5 MB', '', ['big.bin'], [Seeded(1536 * 1024, 12)]);
  Upload('I9 upload two, rz -e', '-e', ['one.bin', 'two.bin'], [Seeded(3000, 13), Seeded(40000, 14)]);
  Upload('I9 upload a name with spaces and Chinese', '', ['a b '#$E4#$B8#$AD#$E6#$96#$87'.bin'], [Seeded(100, 15)]);
  fpSystem('rm -rf ' + Quote(Base));
  WriteLn(Format('zmwsl: %d passed, %d failed', [Passed, Failed]));
  Halt(Failed);
end.
