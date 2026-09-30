unit uzmodemterm;

{ ZMODEM in the terminal (phase 7, design spec 19.7): a stream handler on the core
  that spots a remote sz / rz, asks the host where to save or what to send, runs the
  receiver or the sender of uzmodemsession on the claimed stream, shows one line of
  progress and a summary in the terminal, and hands the stream back.

  WRITTEN FOR THIS LIBRARY from Chuck Forsberg's protocol description, "The ZMODEM
  Inter Application File Transfer Protocol", Rev Oct-14-88 (public domain). No code
  from lrzsz (its licence is not ours).

  How a transfer goes:
    1. Detect finds a hex ZRQINIT (a remote sz: we download) or ZRINIT (a remote rz:
       we upload) with a good CRC, even cut between two pieces (the start kept in a
       carry of at most 20 bytes); the claim starts at its first '*' (sz's "rz\r"
       before it is shown).
    2. Behind ConPTY (Core.WindowsPty says so) and RefuseBehindConPty: one line saying
       ConPTY damages binary data, the abort sequence to the program, the header
       swallowed, the rest handed back -- ConPTY drops every byte from $80 up in both
       directions (spec 19.2 item 12, phase 7 Task 0).
    3. Otherwise OnDownloadRequest / OnUploadRequest. The host must not show a modal
       dialog from the event (it runs inside the core's Feed): it queues one and
       answers later with AcceptDownload(dir) / StartUpload(files) / Decline. Until
       then nothing is sent; what the program repeats meanwhile is kept (bounded).
    4. The transfer: a progress line redrawn in place at most every 200 ms, then a
       summary line; what followed the session is handed back (the shell's prompt).
       Cancel (the host's button), five Ctrl+X in a row (UserInput, wired to the
       core's OnClaimedInput), Reset and RemoveStreamHandler stop it: the abort
       sequence goes to the program, a file not received whole is deleted.
  Received files: the remote name's last element, made safe for Windows (ZmSafeFileName),
  never overwriting (ZmUniqueFileName), with the sender's modification time.

  Uses the core (no LCL): the tests and the WSL console tool run it without a form. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, tyControls.Terminal.Buffer, tyControls.Terminal.Core, uzmodem, uzmodemsession;

resourcestring
  rsZmConPtyRefused = 'ConPTY damages binary data: for ZModem use the pipe mode (tick "Pipe" and restart)';
  rsZmDeclined = 'ZModem transfer declined';
  rsZmCancelledLine = 'ZModem transfer cancelled';
  rsZmFailedLine = 'ZModem transfer failed: %s';
  rsZmReceivedLine = 'Received %d file(s), %s in %s s (%s/s)';
  rsZmSentLine = 'Sent %d file(s), %s in %s s (%s/s)';

type
  TZmodemState = (zsIdle, zsAskDownload, zsAskUpload, zsReceiving, zsSending, zsRefusing);
  TZmodemFinishedEvent = procedure(Sender: TObject; AResult: TZmResult; const AMessage: string) of object;

  { the receiver's files: in a directory, never overwriting, deleted when not whole }
  TZmodemDiskSink = class(TZmFileSink)
  private
    FDir, FPath: string;
    FStream: TFileStream;
    FMTime: Int64;
    FSaved: TStringList;
  public
    constructor Create(const ADir: string);
    destructor Destroy; override;
    function Open(const AName: string; ASize, AMTime: Int64): Boolean; override;
    function Write(AData: PByte; ACount: Integer): Boolean; override;
    procedure Finish(AComplete: Boolean); override;
    property Saved: TStringList read FSaved;         { the files received whole }
  end;

  { the sender's files, in order; one that cannot be opened is left out }
  TZmodemDiskSource = class(TZmFileSource)
  private
    FFiles: TStringList;
    FSizes: array of Int64;
    FNext: Integer;
    FStream: TFileStream;
  public
    constructor Create(AFiles: TStrings);
    destructor Destroy; override;
    function Next(out AName: string; out ASize, AMTime: Int64; out AStream: TStream): Boolean; override;
    function FilesLeft: Integer; override;
    function BytesLeft: Int64; override;
  end;

  TZmodemStreamHandler = class(TTyTerminalStreamHandler)
  private
    FCore: TTyTerminalCore;
    FSession: TTyTerminalStreamSession;
    FState: TZmodemState;
    FEnabled, FRefuseBehindConPty: Boolean;
    FCarry, FClaimPrefix, FPending: RawByteString;
    FDetected: Integer;
    FReceiver: TZmReceiver;
    FSender: TZmSender;
    FSink: TZmodemDiskSink;
    FSource: TZmodemDiskSource;
    FDead: TList;                       { finished machines, freed outside their own calls }
    FCans: Integer;
    FStartMs, FLastProgressMs: Double;
    FProgressLines: Integer;
    FCanSend: TZmCanSendFunc;
    FClock: TTyTerminalClock;
    FUploadFiles: TStringList;          { StartUpload came before rz's ZRINIT was all here }
    FLastSaved: TStringList;
    FLastSummary: string;
    FOnDownloadRequest, FOnUploadRequest: TNotifyEvent;
    FOnProgress: TZmProgressEvent;
    FOnFinished: TZmodemFinishedEvent;
    function NowMs: Double;
    procedure FreeDead;
    procedure Bury;
    procedure MachineSend(Sender: TObject; const AData: RawByteString);
    procedure MachineProgress(Sender: TObject; const AName: string; AFileDone, AFileSize, ATotalDone: Int64);
    procedure MachineDone(Sender: TObject; AResult: TZmResult; const AMessage: string; const ALeftover: RawByteString);
    procedure Show(const AText: string);
    procedure EndClaim(AResult: TZmResult; const AMessage, ALine: string; const ALeftover: RawByteString);
    procedure FeedRefusing;
    procedure TryStartUpload;
  public
    constructor Create(ACore: TTyTerminalCore);    { AddStreamHandler here, Remove in Destroy }
    destructor Destroy; override;
    function Detect(AData: PByte; ACount: Integer; out AClaimAt: Integer): Boolean; override;
    procedure Claimed(ASession: TTyTerminalStreamSession); override;
    procedure Feed(AData: PByte; ACount: Integer); override;
    procedure ClaimEnded(AHow: TTyTerminalClaimEnd); override;
    { the host's answers (any time after the request event, from a queued call) }
    procedure AcceptDownload(const ADirectory: string);
    procedure StartUpload(AFiles: TStrings);
    procedure Decline;                             { abort sequence, release }
    procedure Cancel;                              { same, mid-transfer too }
    { wire Core.OnClaimedInput here: five Ctrl+X (#24) in a row cancel }
    procedure UserInput(const AData: RawByteString);
    procedure Tick(ANowMs: Double);                { the host's timer (100 ms in the example) }
    property State: TZmodemState read FState;
    property Enabled: Boolean read FEnabled write FEnabled;   { False: Detect always answers False }
    { behind ConPTY (Core.WindowsPty.Backend = twpConPty): say so, abort, release }
    property RefuseBehindConPty: Boolean read FRefuseBehindConPty write FRefuseBehindConPty;
    property CanSend: TZmCanSendFunc read FCanSend write FCanSend;
    property Clock: TTyTerminalClock read FClock write FClock;   { nil = TyTermDefaultClock }
    property OnDownloadRequest: TNotifyEvent read FOnDownloadRequest write FOnDownloadRequest;
    property OnUploadRequest: TNotifyEvent read FOnUploadRequest write FOnUploadRequest;
    property OnProgress: TZmProgressEvent read FOnProgress write FOnProgress;
    property OnFinished: TZmodemFinishedEvent read FOnFinished write FOnFinished;
    { the files the last download saved whole }
    property LastSaved: TStringList read FLastSaved;
    { the last transfer's summary line, or why it ended (for a status bar) }
    property LastSummary: string read FLastSummary;
    { FOR THE TESTS (pure query): progress lines shown }
    property ProgressLines: Integer read FProgressLines;
  end;

{ the last path element, Windows-forbidden characters and control characters as '_',
  trailing dots and spaces off, a reserved device name prefixed with '_', '' -> 'file' }
function ZmSafeFileName(const AName: string): string;
{ ADir + AName when free, else 'name (1).ext', 'name (2).ext' ... }
function ZmUniqueFileName(const ADir, AName: string): string;
{ finds a ZRQINIT / ZRINIT hex header with a good CRC; ACarry holds up to 20 bytes of a
  header cut at the end of the previous piece. Answers the header's type (-1 = none)
  and where its first '*' is (0 when it began in the carry). Found: ACarry is then the
  header's bytes that were in the carry (shown already, the claim must add them back
  in front), '' when the header begins in AData. }
function ZmDetectHexStart(AData: PByte; ACount: Integer; var ACarry: RawByteString;
  out AAt: Integer): Integer;
{ 1536 -> '1.5 KB', 3145728 -> '3.0 MB', 12 -> '12 B'; the decimal point is '.' }
function ZmFormatSize(ABytes: Double): string;

implementation

uses
  Math, DateUtils;

const
  { what is kept of the program's repeats while the host has not answered }
  PendingLimit = 65536;
  ProgressEveryMs = 200;
  UploadWindow = 16384;
  CarryMax = 20;

function DotFormat: TFormatSettings;
begin
  Result := DefaultFormatSettings;
  Result.DecimalSeparator := '.';
  Result.ThousandSeparator := ',';
end;

function ZmFormatSize(ABytes: Double): string;
begin
  if ABytes < 1024 then
    Result := FormatFloat('0', ABytes, DotFormat) + ' B'
  else if ABytes < 1024 * 1024 then
    Result := FormatFloat('0.0', ABytes / 1024, DotFormat) + ' KB'
  else
    Result := FormatFloat('0.0', ABytes / (1024 * 1024), DotFormat) + ' MB';
end;

{ ---- file names -------------------------------------------------------------------------- }

function ZmSafeFileName(const AName: string): string;
const
  Reserved: array[0..21] of string = ('CON', 'PRN', 'AUX', 'NUL', 'COM1', 'COM2', 'COM3', 'COM4',
    'COM5', 'COM6', 'COM7', 'COM8', 'COM9', 'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7',
    'LPT8', 'LPT9');
var
  i, p: Integer;
  base: string;
begin
  Result := AName;
  { the last element, either separator }
  p := 0;
  for i := 1 to Length(Result) do
    if Result[i] in ['/', '\'] then
      p := i;
  Result := Copy(Result, p + 1, MaxInt);
  for i := 1 to Length(Result) do
    if (Result[i] in [':', '*', '?', '"', '<', '>', '|']) or (Ord(Result[i]) < 32) or (Ord(Result[i]) = 127) then
      Result[i] := '_';
  while (Result <> '') and (Result[Length(Result)] in ['.', ' ']) do
    SetLength(Result, Length(Result) - 1);
  if Result = '' then
    Exit('file');
  p := Pos('.', Result);
  if p > 0 then base := Copy(Result, 1, p - 1) else base := Result;
  for i := 0 to High(Reserved) do
    if SameText(base, Reserved[i]) then
      Exit('_' + Result);
end;

function ZmUniqueFileName(const ADir, AName: string): string;
var
  dir, base, ext: string;
  n: Integer;
begin
  dir := IncludeTrailingPathDelimiter(ADir);
  Result := dir + AName;
  if not FileExists(Result) and not DirectoryExists(Result) then
    Exit;
  ext := ExtractFileExt(AName);
  base := Copy(AName, 1, Length(AName) - Length(ext));
  n := 1;
  repeat
    Result := dir + base + ' (' + IntToStr(n) + ')' + ext;
    Inc(n);
  until not FileExists(Result) and not DirectoryExists(Result);
end;

{ ---- detection ----------------------------------------------------------------------------- }

function HexVal(C: AnsiChar): Integer;
begin
  case C of
    '0'..'9': Result := Ord(C) - Ord('0');
    'a'..'f': Result := Ord(C) - Ord('a') + 10;
    'A'..'F': Result := Ord(C) - Ord('A') + 10;
  else
    Result := -1;
  end;
end;

{ at S[I] (a '*' followed by ZDLE 'B'): 14 hex digits with a good CRC and type 0 or 1?
  -2 = not all there yet }
function HexHeaderAt(const S: RawByteString; I: Integer): Integer;
var
  b: array[0..6] of Byte;
  k, hi, lo: Integer;
begin
  if I + 2 + 14 > Length(S) then
    Exit(-2);
  for k := 0 to 6 do
  begin
    hi := HexVal(S[I + 3 + k * 2]);
    lo := HexVal(S[I + 4 + k * 2]);
    if (hi < 0) or (lo < 0) then
      Exit(-1);
    b[k] := hi * 16 + lo;
  end;
  if ZmCrc16(0, @b[0], 5) <> (Word(b[5]) shl 8) or b[6] then
    Exit(-1);
  if b[0] in [ZRQINIT, ZRINIT] then
    Result := b[0]
  else
    Result := -1;
end;

function ZmDetectHexStart(AData: PByte; ACount: Integer; var ACarry: RawByteString;
  out AAt: Integer): Integer;
var
  s: RawByteString;
  i, first, t, star, carryLen: Integer;
begin
  AAt := 0;
  Result := -1;
  carryLen := Length(ACarry);
  s := ACarry;
  if ACount > 0 then
  begin
    SetLength(s, carryLen + ACount);
    Move(AData^, s[carryLen + 1], ACount);
  end;
  i := 1;
  while i + 2 <= Length(s) do
  begin
    if (s[i] = '*') and (s[i + 1] = #$18) and (s[i + 2] = 'B') then
    begin
      t := HexHeaderAt(s, i);
      if t >= 0 then
      begin
        first := i;
        while (first > 1) and (s[first - 1] = '*') do
          Dec(first);
        AAt := first - 1 - carryLen;
        if AAt < 0 then
        begin
          { the header began in the carry: those bytes are on screen already }
          ACarry := Copy(s, first, carryLen - first + 1);
          AAt := 0;
        end
        else
          ACarry := '';
        Exit(t);
      end;
      if t = -2 then
        Break;                           { cut at the end: kept below }
    end;
    Inc(i);
  end;
  { nothing: keep the end from its last '*' run on, when it may be a header's start }
  ACarry := '';
  star := 0;
  for i := Length(s) downto Max(1, Length(s) - CarryMax + 1) do
    if s[i] = '*' then
    begin
      star := i;
      Break;
    end;
  if star > 0 then
  begin
    while (star > 1) and (star > Length(s) - CarryMax + 1) and (s[star - 1] = '*') do
      Dec(star);
    ACarry := Copy(s, star, MaxInt);
  end;
end;

{ ---- the disk sink and source --------------------------------------------------------------- }

constructor TZmodemDiskSink.Create(const ADir: string);
begin
  inherited Create;
  FDir := ADir;
  FSaved := TStringList.Create;
end;

destructor TZmodemDiskSink.Destroy;
begin
  if FStream <> nil then
    Finish(False);
  FSaved.Free;
  inherited Destroy;
end;

function TZmodemDiskSink.Open(const AName: string; ASize, AMTime: Int64): Boolean;
begin
  if FStream <> nil then
    Finish(False);
  FPath := ZmUniqueFileName(FDir, ZmSafeFileName(AName));
  FMTime := AMTime;
  try
    FStream := TFileStream.Create(FPath, fmCreate);
    Result := True;
  except
    FStream := nil;
    Result := False;
  end;
end;

function TZmodemDiskSink.Write(AData: PByte; ACount: Integer): Boolean;
begin
  Result := False;
  if FStream = nil then
    Exit;
  try
    FStream.WriteBuffer(AData^, ACount);
    Result := True;
  except
    Result := False;
  end;
end;

procedure TZmodemDiskSink.Finish(AComplete: Boolean);
begin
  if FStream = nil then
    Exit;
  FreeAndNil(FStream);
  if AComplete then
  begin
    if FMTime > 0 then
      FileSetDate(FPath, DateTimeToFileDate(UniversalTimeToLocal(UnixToDateTime(FMTime))));
    FSaved.Add(FPath);
  end
  else
    DeleteFile(FPath);                   { spec 19.7: nothing half received is left }
end;

constructor TZmodemDiskSource.Create(AFiles: TStrings);
var
  i: Integer;
  sr: TSearchRec;
begin
  inherited Create;
  FFiles := TStringList.Create;
  for i := 0 to AFiles.Count - 1 do
    if FindFirst(AFiles[i], faAnyFile and not faDirectory, sr) = 0 then
    begin
      FFiles.Add(AFiles[i]);
      SetLength(FSizes, Length(FSizes) + 1);
      FSizes[High(FSizes)] := sr.Size;
      FindClose(sr);
    end;
end;

destructor TZmodemDiskSource.Destroy;
begin
  FStream.Free;
  FFiles.Free;
  inherited Destroy;
end;

function TZmodemDiskSource.Next(out AName: string; out ASize, AMTime: Int64; out AStream: TStream): Boolean;
var
  age: LongInt;
begin
  Result := False;
  AName := '';
  ASize := 0;
  AMTime := 0;
  AStream := nil;
  FreeAndNil(FStream);
  while FNext < FFiles.Count do
  begin
    try
      FStream := TFileStream.Create(FFiles[FNext], fmOpenRead or fmShareDenyWrite);
    except
      FStream := nil;
    end;
    Inc(FNext);
    if FStream = nil then
      Continue;
    AName := ExtractFileName(FFiles[FNext - 1]);
    ASize := FStream.Size;
    age := FileAge(FFiles[FNext - 1]);
    if age <> -1 then
      AMTime := DateTimeToUnix(LocalTimeToUniversal(FileDateToDateTime(age)));
    AStream := FStream;
    Exit(True);
  end;
end;

function TZmodemDiskSource.FilesLeft: Integer;
begin
  Result := FFiles.Count - FNext;
end;

function TZmodemDiskSource.BytesLeft: Int64;
var
  i: Integer;
begin
  Result := 0;
  for i := FNext to High(FSizes) do
    Inc(Result, FSizes[i]);
end;

{ ---- TZmodemStreamHandler ---------------------------------------------------------------------- }

constructor TZmodemStreamHandler.Create(ACore: TTyTerminalCore);
begin
  inherited Create;
  FCore := ACore;
  FEnabled := True;
  FRefuseBehindConPty := True;
  FDetected := -1;
  FLastProgressMs := -1;
  FDead := TList.Create;
  FLastSaved := TStringList.Create;
  FCore.AddStreamHandler(Self);
end;

destructor TZmodemStreamHandler.Destroy;
begin
  { a claim of ours ends here (ClaimEnded: the program is told to stop) }
  FCore.RemoveStreamHandler(Self);
  Bury;
  FreeDead;
  FDead.Free;
  FUploadFiles.Free;
  FLastSaved.Free;
  inherited Destroy;
end;

function TZmodemStreamHandler.NowMs: Double;
begin
  if Assigned(FClock) then
    Result := FClock()
  else
    Result := TyTermDefaultClock;
end;

{ the machines and their files, off stage: freed later, never inside their own call }
procedure TZmodemStreamHandler.Bury;
begin
  if FReceiver <> nil then
  begin
    FReceiver.OnSend := nil;
    FReceiver.OnDone := nil;
    FReceiver.OnProgress := nil;
    FDead.Add(FReceiver);
    FReceiver := nil;
  end;
  if FSender <> nil then
  begin
    FSender.OnSend := nil;
    FSender.OnDone := nil;
    FSender.OnProgress := nil;
    FDead.Add(FSender);
    FSender := nil;
  end;
  if FSink <> nil then
  begin
    FDead.Add(FSink);
    FSink := nil;
  end;
  if FSource <> nil then
  begin
    FDead.Add(FSource);
    FSource := nil;
  end;
end;

procedure TZmodemStreamHandler.FreeDead;
var
  i: Integer;
begin
  { the machines before the sink / source they write through (added in that order) }
  for i := 0 to FDead.Count - 1 do
    TObject(FDead[i]).Free;
  FDead.Clear;
end;

procedure TZmodemStreamHandler.Show(const AText: string);
begin
  if (FSession <> nil) and FSession.Active then
    FSession.ShowText(AText);
end;

function TZmodemStreamHandler.Detect(AData: PByte; ACount: Integer; out AClaimAt: Integer): Boolean;
var
  at, t: Integer;
begin
  AClaimAt := 0;
  Result := False;
  if not FEnabled or (FState <> zsIdle) then
    Exit;
  t := ZmDetectHexStart(AData, ACount, FCarry, at);
  if t < 0 then
    Exit;
  FDetected := t;
  FClaimPrefix := FCarry;                { the header's start that was shown already }
  FCarry := '';
  AClaimAt := at;
  Result := True;
end;

procedure TZmodemStreamHandler.Claimed(ASession: TTyTerminalStreamSession);
begin
  FreeDead;
  FSession := ASession;
  FPending := FClaimPrefix;
  FClaimPrefix := '';
  FCans := 0;
  if FRefuseBehindConPty and (FCore.WindowsPty.Backend = twpConPty) then
  begin
    FState := zsRefusing;
    Show(rsZmConPtyRefused + #13#10);
    FSession.SendRaw(ZmAbortSequence);
    { the header itself comes in Feed: swallowed there, the rest handed back }
    FeedRefusing;
    Exit;
  end;
  if FDetected = ZRQINIT then
  begin
    FState := zsAskDownload;
    if Assigned(FOnDownloadRequest) then
      FOnDownloadRequest(Self);
  end
  else
  begin
    FState := zsAskUpload;
    if Assigned(FOnUploadRequest) then
      FOnUploadRequest(Self);
  end;
end;

{ refusing: once the header is all in FPending, the bytes after it go back }
procedure TZmodemStreamHandler.FeedRefusing;
var
  i, e: Integer;
begin
  i := Pos(#$18'B', FPending);
  if (i = 0) or (i + 1 + 14 > Length(FPending)) then
    Exit;
  e := i + 1 + 14;                       { the last hex digit }
  while (e < Length(FPending)) and (e - (i + 15) < 3) and (FPending[e + 1] in [#$0D, #$8D, #$0A, #$8A, #$11]) do
    Inc(e);
  EndClaim(zrError, rsZmConPtyRefused, '', Copy(FPending, e + 1, MaxInt));
end;

procedure TZmodemStreamHandler.Feed(AData: PByte; ACount: Integer);
var
  s: RawByteString;
begin
  s := '';
  SetLength(s, ACount);
  if ACount > 0 then
    Move(AData^, s[1], ACount);
  case FState of
    zsRefusing:
      begin
        FPending := FPending + s;
        FeedRefusing;
      end;
    zsAskDownload, zsAskUpload:
      begin
        { the program repeats itself while the host asks: kept for the machine }
        FPending := FPending + s;
        if Length(FPending) > PendingLimit then
          FPending := Copy(FPending, Length(FPending) - PendingLimit + 1, MaxInt);
        if (FState = zsAskUpload) and (FUploadFiles <> nil) then
          TryStartUpload;
      end;
    zsReceiving:
      if FReceiver <> nil then
        FReceiver.Input(@s[1], Length(s), NowMs);
    zsSending:
      if FSender <> nil then
        FSender.Input(@s[1], Length(s), NowMs);
  end;
end;

procedure TZmodemStreamHandler.ClaimEnded(AHow: TTyTerminalClaimEnd);
begin
  { the host ended the claim (Reset, RemoveStreamHandler): stop the program; the
    session still sends during this call }
  case FState of
    zsReceiving:
      if FReceiver <> nil then
        FReceiver.Cancel;                { -> MachineDone: the half file deleted }
    zsSending:
      if FSender <> nil then
        FSender.Cancel;
    zsAskDownload, zsAskUpload:
      begin
        FSession.SendRaw(ZmAbortSequence);
        EndClaim(zrCancelledHere, rsZmCancelledLine, '', '');
      end;
  end;
  Bury;
  FState := zsIdle;
  FPending := '';
  FSession := nil;
end;

procedure TZmodemStreamHandler.MachineSend(Sender: TObject; const AData: RawByteString);
begin
  if FSession <> nil then
    FSession.SendRaw(AData);
end;

procedure TZmodemStreamHandler.MachineProgress(Sender: TObject; const AName: string; AFileDone, AFileSize,
  ATotalDone: Int64);
var
  now, secs: Double;
  pct: Integer;
  arrow, line: string;
begin
  if Assigned(FOnProgress) then
    FOnProgress(Self, AName, AFileDone, AFileSize, ATotalDone);
  now := NowMs;
  if (FLastProgressMs >= 0) and (now - FLastProgressMs < ProgressEveryMs) then
    Exit;
  FLastProgressMs := now;
  if FState = zsSending then
    arrow := #$E2#$86#$91                { U+2191 }
  else
    arrow := #$E2#$86#$93;               { U+2193 }
  if AFileSize > 0 then
    pct := Round(AFileDone * 100 / AFileSize)
  else
    pct := 100;
  secs := (now - FStartMs) / 1000;
  line := #13#27'[K' + arrow + ' ' + AName + '  ' + ZmFormatSize(AFileDone) + ' / ' + ZmFormatSize(AFileSize)
    + '  ' + IntToStr(pct) + '%';
  if secs > 0 then
    line := line + '  ' + ZmFormatSize(ATotalDone / secs) + '/s';
  Inc(FProgressLines);
  Show(line);
end;

procedure TZmodemStreamHandler.MachineDone(Sender: TObject; AResult: TZmResult; const AMessage: string;
  const ALeftover: RawByteString);
var
  secs, total: Double;
  files: Integer;
  line: string;
begin
  secs := (NowMs - FStartMs) / 1000;
  if (Sender is TZmReceiver) and (FSink <> nil) then
    FLastSaved.Assign(FSink.Saved);
  if Sender is TZmReceiver then
  begin
    files := TZmReceiver(Sender).Files;
    total := TZmReceiver(Sender).TotalBytes;
  end
  else
  begin
    files := TZmSender(Sender).Files;
    total := TZmSender(Sender).TotalBytes;
  end;
  case AResult of
    zrOk:
      begin
        if secs <= 0 then
          secs := 0.001;
        if Sender is TZmReceiver then
          line := Format(rsZmReceivedLine, [files, ZmFormatSize(total), FormatFloat('0.0', secs, DotFormat),
            ZmFormatSize(total / secs)])
        else
          line := Format(rsZmSentLine, [files, ZmFormatSize(total), FormatFloat('0.0', secs, DotFormat),
            ZmFormatSize(total / secs)]);
      end;
    zrCancelledHere, zrCancelledThere:
      line := rsZmCancelledLine;
  else
    line := Format(rsZmFailedLine, [AMessage]);
  end;
  EndClaim(AResult, AMessage, line, ALeftover);
end;

{ a transfer, a refusal or a decline is over: the line, the stream back, the host told }
procedure TZmodemStreamHandler.EndClaim(AResult: TZmResult; const AMessage, ALine: string;
  const ALeftover: RawByteString);
var
  s: TTyTerminalStreamSession;
begin
  if ALine <> '' then
  begin
    Show(#13#27'[K' + ALine + #13#10);
    FLastSummary := ALine;
  end
  else
    FLastSummary := AMessage;
  Bury;
  FState := zsIdle;
  FPending := '';
  FreeAndNil(FUploadFiles);
  FLastProgressMs := -1;
  s := FSession;
  FSession := nil;
  if (s <> nil) and s.Active then
    s.Release(ALeftover);
  if Assigned(FOnFinished) then
    FOnFinished(Self, AResult, AMessage);
end;

procedure TZmodemStreamHandler.AcceptDownload(const ADirectory: string);
var
  s: RawByteString;
begin
  if FState <> zsAskDownload then
    Exit;
  FreeDead;
  FSink := TZmodemDiskSink.Create(ADirectory);
  FReceiver := TZmReceiver.Create(FSink);
  FReceiver.OnSend := @MachineSend;
  FReceiver.OnProgress := @MachineProgress;
  FReceiver.OnDone := @MachineDone;
  FState := zsReceiving;
  FStartMs := NowMs;
  FLastProgressMs := -1;
  FReceiver.Start(FStartMs);
  { what sz said while the host asked (its ZRQINIT, repeated) }
  s := FPending;
  FPending := '';
  if (s <> '') and (FReceiver <> nil) then
    FReceiver.Input(@s[1], Length(s), NowMs);
end;

type
  TZmHeaderCollector = class
  public
    Last: TZmHeader;
    Found: Boolean;
    procedure OnHeader(const AHeader: TZmHeader; AKind: TZmHeaderKind);
  end;

procedure TZmHeaderCollector.OnHeader(const AHeader: TZmHeader; AKind: TZmHeaderKind);
begin
  if AHeader.FrameType = ZRINIT then
  begin
    Last := AHeader;
    Found := True;
  end;
end;

procedure TZmodemStreamHandler.StartUpload(AFiles: TStrings);
begin
  if FState <> zsAskUpload then
    Exit;
  FreeDead;
  FreeAndNil(FUploadFiles);
  FUploadFiles := TStringList.Create;
  FUploadFiles.Assign(AFiles);
  TryStartUpload;
end;

{ the sender starts from the last ZRINIT rz sent (its flags: CRC-32, ESCCTL; its buffer
  size) -- answered from Claimed, the header may not be all here yet: the next Feed
  tries again }
procedure TZmodemStreamHandler.TryStartUpload;
var
  r: TZmReader;
  c: TZmHeaderCollector;
  init: TZmHeader;
  found: Boolean;
begin
  r := TZmReader.Create;
  c := TZmHeaderCollector.Create;
  try
    r.OnHeader := @c.OnHeader;
    if FPending <> '' then
      r.Push(@FPending[1], Length(FPending));
    found := c.Found;
    init := c.Last;
  finally
    c.Free;
    r.Free;
  end;
  if not found then
    Exit;
  FPending := '';
  FSource := TZmodemDiskSource.Create(FUploadFiles);
  FreeAndNil(FUploadFiles);
  FSender := TZmSender.Create(FSource);
  FSender.OnSend := @MachineSend;
  FSender.OnProgress := @MachineProgress;
  FSender.OnDone := @MachineDone;
  FSender.CanSend := FCanSend;
  { what is on its way when rz asks for a byte again reaches it as garbage, and rz
    gives up after about 40 KB of that: keep less than that unacknowledged }
  FSender.Window := UploadWindow;
  FState := zsSending;
  FStartMs := NowMs;
  FLastProgressMs := -1;
  FSender.Start(init, FStartMs);
end;

procedure TZmodemStreamHandler.Decline;
begin
  if not (FState in [zsAskDownload, zsAskUpload]) then
    Exit;
  if FSession <> nil then
    FSession.SendRaw(ZmAbortSequence);
  EndClaim(zrCancelledHere, rsZmDeclined, rsZmDeclined, '');
end;

procedure TZmodemStreamHandler.Cancel;
begin
  case FState of
    zsAskDownload, zsAskUpload:
      Decline;
    zsReceiving:
      if FReceiver <> nil then
        FReceiver.Cancel;
    zsSending:
      if FSender <> nil then
        FSender.Cancel;
  end;
end;

procedure TZmodemStreamHandler.UserInput(const AData: RawByteString);
var
  i: Integer;
begin
  for i := 1 to Length(AData) do
    if AData[i] = #24 then
    begin
      Inc(FCans);
      if FCans >= 5 then
      begin
        FCans := 0;
        Cancel;
        Exit;
      end;
    end
    else
      FCans := 0;
end;

procedure TZmodemStreamHandler.Tick(ANowMs: Double);
begin
  { never inside a machine's own call here: what finished can go }
  FreeDead;
  if FReceiver <> nil then
    FReceiver.Tick(ANowMs)
  else if FSender <> nil then
    FSender.Tick(ANowMs);
end;

end.
