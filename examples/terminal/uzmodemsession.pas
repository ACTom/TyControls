unit uzmodemsession;

{ The ZMODEM receiver and sender of the terminal example (phase 7, design spec 19.7),
  on top of uzmodem's frames. Neither touches a file, a clock or a wire itself: bytes
  go out through OnSend, come in through Input, files through a sink / a source, and
  the time is the host's (Tick, ANowMs) -- so the tests drive them with recorded bytes
  and an injected clock, and the terminal glue (uzmodemterm) with the terminal's.

  WRITTEN FOR THIS LIBRARY from Chuck Forsberg's protocol description, "The ZMODEM
  Inter Application File Transfer Protocol", Rev Oct-14-88 (public domain). No code
  from lrzsz (GPL); lrzsz is only the program the tests talk to.

  What is done (spec 19.7 "范围"):
    - the receiver answers with hex headers as rz does: ZRINIT (CANFDX | CANOVIO |
      CANFC32, ESCCTL on request, buffer 0 = full streaming), ZRPOS, ZACK, ZSKIP,
      ZFIN; takes 16- and 32-bit data subpackets up to MaxSubpacket (8 KB, sz -8);
      a bad subpacket is answered by ZRPOS at the last good byte and the data is
      dropped until a ZDATA at that place; ZSINIT is acknowledged and otherwise
      ignored; ZCOMMAND is REFUSED (the other side asking this machine to run a
      command): an abort and zrError; ZFREECNT and ZCHALLENGE get the simplest ZACK;
    - the sender sends binary headers (CRC-32 when the receiver can), 1 KB
      subpackets streamed with ZCRCG, or ZCRCW at the end of each window when the
      receiver gave a buffer size; a ZRPOS goes back to that place; ZNAK repeats the
      last header; a file resumed (ZCRESUM) is sent from the start;
    - after ZFIN the receiver eats at most two 'O's (a second at most, then it ends);
      the sender sends "OO" after the receiver's ZFIN. What follows in the same
      Input goes to OnDone's ALeftover: the terminal shows it (the shell's prompt).
      A sender whose ZFIN is not answered sends it twice more (again at once when
      the receiver repeats its ZRINIT), then ends zrOk: every file was acknowledged
      already, and the receiver may have gone (sz does the same);
    - waiting for an answer longer than TimeoutMs repeats the last one, MaxRetries
      times at one place, then the abort sequence and zrTimeout. Every header or
      subpacket that arrives resets the count;
    - five CANs, ZCAN or ZABORT from the other side: zrCancelledThere. Cancel here:
      the abort sequence (10 CAN, 10 BS, as lrzsz) and zrCancelledHere. A file not
      received whole is Finish(False) -- the sink deletes it.

  Not re-entrant: OnSend must not feed the other side synchronously back into Input
  (the tests queue; the terminal writes to the PTY's queue). OnDone may not free the
  object it came from (it is still on the stack). Only SysUtils and Classes. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, uzmodem;

type
  TZmResult = (zrOk, zrCancelledHere, zrCancelledThere, zrTimeout, zrError);
  TZmSendEvent = procedure(Sender: TObject; const AData: RawByteString) of object;
  TZmProgressEvent = procedure(Sender: TObject; const AName: string; AFileDone, AFileSize,
    ATotalDone: Int64) of object;
  { ALeftover: bytes after the session's end (after "OO", after the peer's ZFIN) }
  TZmDoneEvent = procedure(Sender: TObject; AResult: TZmResult; const AMessage: string;
    const ALeftover: RawByteString) of object;

  TZmFileSink = class          { the receiver writes through it }
  public
    { False = skip this file (ZSKIP); AName is the peer's, untouched }
    function Open(const AName: string; ASize, AMTime: Int64): Boolean; virtual; abstract;
    function Write(AData: PByte; ACount: Integer): Boolean; virtual; abstract;
    { AComplete False: cancelled or failed half way }
    procedure Finish(AComplete: Boolean); virtual; abstract;
  end;

  TZmFileSource = class        { the sender reads through it }
  public
    { the next file; False = none left. AStream belongs to the source. }
    function Next(out AName: string; out ASize, AMTime: Int64; out AStream: TStream): Boolean; virtual; abstract;
    function FilesLeft: Integer; virtual; abstract;
    function BytesLeft: Int64; virtual; abstract;
  end;

  { what the one side waits for, for timeouts }
  TZmReplyKind = (zrkNone, zrkRinit, zrkRpos);
  TZmReceiverState = (zrcIdle, zrcHeaders, zrcData, zrcWaitOO, zrcDone);

  TZmReceiver = class
  private
    FSink: TZmFileSink;
    FReader: TZmReader;
    FState: TZmReceiverState;
    FDone: Boolean;
    FFileOpen: Boolean;
    FName: string;
    FSize, FPos, FTotal: Int64;
    FFiles: Integer;
    FLast: TZmReplyKind;
    FLastActivity, FNow, FOStart: Double;
    FRetries, FErrors, FErrCountAt: Integer;
    FErrPos: Int64;
    FOs, FTailEaten: Integer;
    FLastHeaderType: Integer;              { what the next subpacket belongs to }
    FFinishing: Boolean;
    FResult: TZmResult;
    FMessage: string;
    FEscapeControl: Boolean;
    FTimeoutMs, FMaxRetries, FMaxSubpacket: Integer;
    FOnSend: TZmSendEvent;
    FOnProgress: TZmProgressEvent;
    FOnDone: TZmDoneEvent;
    procedure Send(const AData: RawByteString);
    procedure SendHex(AType: Byte; APos: Cardinal);
    procedure SendRinit;
    procedure Rpos;
    procedure Activity;
    procedure Header(const AHeader: TZmHeader; AKind: TZmHeaderKind);
    procedure Data(const AData: RawByteString; AEnd: Byte; ACrcOk: Boolean);
    procedure DataError;
    procedure Cancelled(Sender: TObject);
    procedure FileInfo(const AData: RawByteString);
    procedure CloseFile(AComplete: Boolean);
    { ends the session from inside Input: the reader stops, Input hands OnDone the rest }
    procedure EndInInput(AResult: TZmResult; const AMessage: string);
    procedure Abort(AResult: TZmResult; const AMessage: string);
    procedure Finish(AResult: TZmResult; const AMessage: string; const ALeftover: RawByteString);
  public
    constructor Create(ASink: TZmFileSink);
    destructor Destroy; override;
    procedure Start(ANowMs: Double);                 { sends ZRINIT }
    { consumed until the session ends; the rest reaches OnDone's ALeftover }
    procedure Input(AData: PByte; ACount: Integer; ANowMs: Double);
    procedure Tick(ANowMs: Double);                  { timeouts and retries }
    procedure Cancel;                                { ZmAbortSequence, then OnDone(zrCancelledHere) }
    property Done: Boolean read FDone;
    property Files: Integer read FFiles;             { received whole }
    property TotalBytes: Int64 read FTotal;
    property OnSend: TZmSendEvent read FOnSend write FOnSend;
    property OnProgress: TZmProgressEvent read FOnProgress write FOnProgress;
    property OnDone: TZmDoneEvent read FOnDone write FOnDone;
    { options, before Start }
    property EscapeControl: Boolean read FEscapeControl write FEscapeControl;   { advertise ESCCTL (tests); default False }
    property TimeoutMs: Integer read FTimeoutMs write FTimeoutMs;               { default 10000 }
    property MaxRetries: Integer read FMaxRetries write FMaxRetries;            { default 10 }
    property MaxSubpacket: Integer read FMaxSubpacket write FMaxSubpacket;      { default ZmMaxRecvSubpacket }
    { FOR THE TESTS (pure queries): ZRPOS sent after a bad subpacket, timeouts repeated }
    property Errors: Integer read FErrors;
  end;

  TZmCanSendFunc = function: Integer of object;       { bytes the host takes now }
  TZmCrcMode = (zcmAuto, zcmCrc16, zcmCrc32);
  TZmSenderState = (zsnIdle, zsnFile, zsnData, zsnWaitAck, zsnEof, zsnFin, zsnDone);

  TZmSender = class
  private
    FSource: TZmFileSource;
    FReader: TZmReader;
    FState: TZmSenderState;
    FDone: Boolean;
    FCrcMode: TZmCrcMode;
    FCrc32: Boolean;
    FEsc: TZmEscaper;
    FBufSize: Integer;
    FName: string;
    FSize, FMTime, FPos, FWindowStart, FTotal: Int64;
    FStream: TStream;
    FLastHeader: RawByteString;
    FLastActivity, FNow: Double;
    FRetries, FRepositions: Integer;
    FFiles: Integer;
    FFinishing: Boolean;
    FResult: TZmResult;
    FMessage: string;
    FTimeoutMs, FMaxRetries: Integer;
    FCanSend: TZmCanSendFunc;
    FOnSend: TZmSendEvent;
    FOnProgress: TZmProgressEvent;
    FOnDone: TZmDoneEvent;
    FBuf: array of Byte;
    procedure Send(const AData: RawByteString);
    procedure SendLast(const AData: RawByteString);
    function GetUseCrc32: Boolean;
    procedure SetUseCrc32(AValue: Boolean);
    procedure NextFile;
    procedure StartData(APos: Int64);
    procedure Pump;
    procedure Header(const AHeader: TZmHeader; AKind: TZmHeaderKind);
    procedure Data(const AData: RawByteString; AEnd: Byte; ACrcOk: Boolean);
    procedure Cancelled(Sender: TObject);
    procedure EndInInput(AResult: TZmResult; const AMessage: string);
    procedure Abort(AResult: TZmResult; const AMessage: string);
    procedure Finish(AResult: TZmResult; const AMessage: string; const ALeftover: RawByteString);
  public
    constructor Create(ASource: TZmFileSource);
    destructor Destroy; override;
    { AInit: the ZRINIT that started it (flags, buffer size) }
    procedure Start(const AInit: TZmHeader; ANowMs: Double);
    procedure Input(AData: PByte; ACount: Integer; ANowMs: Double);
    procedure Tick(ANowMs: Double);                  { timeouts; and more data if CanSend allows }
    procedure Cancel;
    property Done: Boolean read FDone;
    property Files: Integer read FFiles;             { acknowledged whole (the ZRINIT after ZEOF) }
    property TotalBytes: Int64 read FTotal;
    property CanSend: TZmCanSendFunc read FCanSend write FCanSend;   { nil = unlimited (tests) }
    property OnSend: TZmSendEvent read FOnSend write FOnSend;
    property OnProgress: TZmProgressEvent read FOnProgress write FOnProgress;
    property OnDone: TZmDoneEvent read FOnDone write FOnDone;
    { default: when the ZRINIT has CANFC32; set before Start to force one }
    property UseCrc32: Boolean read GetUseCrc32 write SetUseCrc32;
    property TimeoutMs: Integer read FTimeoutMs write FTimeoutMs;
    property MaxRetries: Integer read FMaxRetries write FMaxRetries;
    { FOR THE TESTS (pure query): times a ZRPOS sent the data back }
    property Repositions: Integer read FRepositions;
  end;

resourcestring
  rsZmCommandRefused = 'the sender asked to run a command; refused';
  rsZmTimeout = 'no answer from the other side';
  rsZmTooManyErrors = 'too many errors at one place';
  rsZmCancelledHere = 'cancelled';
  rsZmCancelledThere = 'cancelled by the other side';
  rsZmWriteFailed = 'the file could not be written';
  rsZmFileError = 'the other side could not write the file';

implementation

const
  RinitFlags = CANFDX or CANOVIO or CANFC32;
  { after ZFIN: at most this long for "OO" }
  OverAndOutMs = 1000;
  { the sender repeats its ZFIN this often before it ends without the answer }
  FinRetries = 2;

{ the CR LF and XON after a hex header, where a session ends right after one }
function SkipHexTail(AData: PByte; ACount, AFrom: Integer): Integer;
var
  n: Integer;
begin
  Result := AFrom;
  n := 0;
  while (Result < ACount) and (n < 3) and (AData[Result] in [$0D, $8D, $0A, $8A, $11]) do
  begin
    Inc(Result);
    Inc(n);
  end;
end;

function BytesAt(AData: PByte; AFrom, ACount: Integer): RawByteString;
begin
  Result := '';
  if AFrom >= ACount then
    Exit;
  SetLength(Result, ACount - AFrom);
  Move(AData[AFrom], Result[1], ACount - AFrom);
end;

{ what an Input that ended the session hands back from AFrom on: after a normal end
  the rest (the CR LF of the last hex header skipped); after the other side aborted
  the rest without its CANs and backspaces (the shell's prompt that follows); after
  an error of ours nothing -- the rest belongs to a protocol we left }
function LeftoverOf(AResult: TZmResult; AData: PByte; AFrom, ACount: Integer): RawByteString;
begin
  case AResult of
    zrOk:
      Result := BytesAt(AData, SkipHexTail(AData, ACount, AFrom), ACount);
    zrCancelledThere:
      begin
        while (AFrom < ACount) and (AData[AFrom] in [$18, $08]) do
          Inc(AFrom);
        Result := BytesAt(AData, AFrom, ACount);
      end;
  else
    Result := '';
  end;
end;

{ ==== TZmReceiver ========================================================================= }

constructor TZmReceiver.Create(ASink: TZmFileSink);
begin
  inherited Create;
  FSink := ASink;
  FReader := TZmReader.Create;
  FReader.OnHeader := @Header;
  FReader.OnData := @Data;
  FReader.OnCancel := @Cancelled;
  FTimeoutMs := 10000;
  FMaxRetries := 10;
  FMaxSubpacket := ZmMaxRecvSubpacket;
end;

destructor TZmReceiver.Destroy;
begin
  if FFileOpen then
    CloseFile(False);
  FReader.Free;
  inherited Destroy;
end;

procedure TZmReceiver.Send(const AData: RawByteString);
begin
  if Assigned(FOnSend) then
    FOnSend(Self, AData);
end;

procedure TZmReceiver.SendHex(AType: Byte; APos: Cardinal);
begin
  Send(ZmEncodeHexHeader(ZmPosHeader(AType, APos)));
end;

procedure TZmReceiver.SendRinit;
var
  f: Byte;
begin
  f := RinitFlags;
  if FEscapeControl then
    f := f or ESCCTL;
  { buffer size 0 (P0, P1): stream without windows }
  Send(ZmEncodeHexHeader(ZmFlagsHeader(ZRINIT, f, 0, 0, 0)));
  FLast := zrkRinit;
end;

procedure TZmReceiver.Rpos;
begin
  SendHex(ZRPOS, Cardinal(FPos));
  FLast := zrkRpos;
end;

procedure TZmReceiver.Activity;
begin
  FLastActivity := FNow;
  FRetries := 0;
end;

procedure TZmReceiver.Start(ANowMs: Double);
begin
  FNow := ANowMs;
  FReader.MaxSubpacket := FMaxSubpacket;
  FState := zrcHeaders;
  SendRinit;
  Activity;
end;

procedure TZmReceiver.CloseFile(AComplete: Boolean);
begin
  if not FFileOpen then
    Exit;
  FFileOpen := False;
  FSink.Finish(AComplete);
end;

procedure TZmReceiver.EndInInput(AResult: TZmResult; const AMessage: string);
begin
  FFinishing := True;
  FResult := AResult;
  FMessage := AMessage;
  FReader.Stop;
end;

procedure TZmReceiver.Abort(AResult: TZmResult; const AMessage: string);
begin
  Send(ZmAbortSequence);
  CloseFile(False);
  EndInInput(AResult, AMessage);
end;

procedure TZmReceiver.Finish(AResult: TZmResult; const AMessage: string; const ALeftover: RawByteString);
begin
  if FDone then
    Exit;
  FDone := True;
  FState := zrcDone;
  CloseFile(False);                      { a file still open was not received whole }
  if Assigned(FOnDone) then
    FOnDone(Self, AResult, AMessage, ALeftover);
end;

procedure TZmReceiver.FileInfo(const AData: RawByteString);
var
  name: string;
  size, mtime: Int64;
  mode: Cardinal;
begin
  if not ZmParseFileInfo(AData, name, size, mtime, mode) then
  begin
    SendHex(ZSKIP, 0);
    Exit;
  end;
  if FFileOpen then
  begin
    { the same ZFILE again (the other side did not hear our ZRPOS): not a new file }
    if name = FName then
    begin
      Rpos;
      Exit;
    end;
    CloseFile(False);
  end;
  if not FSink.Open(name, size, mtime) then
  begin
    SendHex(ZSKIP, 0);
    FLast := zrkRinit;
    Exit;
  end;
  FFileOpen := True;
  FName := name;
  FSize := size;
  FPos := 0;
  FErrPos := -1;
  Rpos;
end;

procedure TZmReceiver.Header(const AHeader: TZmHeader; AKind: TZmHeaderKind);
var
  pos: Cardinal;
begin
  if FFinishing then
    Exit;
  Activity;
  FLastHeaderType := AHeader.FrameType;
  pos := ZmHeaderPos(AHeader);
  case AHeader.FrameType of
    ZRQINIT:
      if not FFileOpen then
        SendRinit;                       { sz asks again: we are here }
    ZSINIT, ZFILE:
      ;                                  { the subpacket follows (Data) }
    ZDATA:
      if not FFileOpen then
        FReader.DropData                 { no file: nothing to put it in (a timeout repeats our answer) }
      else if pos <> FPos then
        DataError
      else
        FState := zrcData;
    ZEOF:
      { at the end we have: the file is whole; elsewhere a stale ZEOF (spec) }
      if FFileOpen and (pos = FPos) then
      begin
        CloseFile(True);
        Inc(FFiles);
        FState := zrcHeaders;
        SendRinit;
      end;
    ZFIN:
      begin
        SendHex(ZFIN, 0);
        FLast := zrkNone;
        FState := zrcWaitOO;
        FOStart := FNow;
        FOs := 0;
        FTailEaten := 0;
        FReader.Stop;                    { Input counts the O's itself }
      end;
    ZCOMMAND:
      Abort(zrError, rsZmCommandRefused);
    ZFREECNT:
      SendHex(ZACK, $7FFFFFFF);
    ZCHALLENGE:
      SendHex(ZACK, pos);
    ZCAN, ZABORT:
      begin
        CloseFile(False);
        EndInInput(zrCancelledThere, rsZmCancelledThere);
      end;
    ZFERR:
      begin
        CloseFile(False);
        EndInInput(zrError, rsZmFileError);
      end;
    ZNAK:
      case FLast of
        zrkRinit: SendRinit;
        zrkRpos: Rpos;
      end;
  end;
end;

{ a bad subpacket, or a ZDATA at the wrong place: back to the last good byte; at one
  place at most MaxRetries times }
procedure TZmReceiver.DataError;
begin
  if FErrPos = FPos then
    Inc(FErrCountAt)
  else
  begin
    FErrPos := FPos;
    FErrCountAt := 1;
  end;
  Inc(FErrors);
  if FErrCountAt > FMaxRetries then
  begin
    Abort(zrError, rsZmTooManyErrors);
    Exit;
  end;
  FReader.DropData;
  FState := zrcHeaders;
  Rpos;
end;

procedure TZmReceiver.Data(const AData: RawByteString; AEnd: Byte; ACrcOk: Boolean);
begin
  if FFinishing then
    Exit;
  if not ACrcOk then
  begin
    if (FLastHeaderType = ZDATA) and FFileOpen then
      DataError
    else
      SendHex(ZNAK, 0);                  { the file information or ZSINIT: again, please }
    Exit;
  end;
  Activity;
  case FLastHeaderType of
    ZSINIT:
      SendHex(ZACK, 1);                  { its Attn string is not used }
    ZFILE:
      FileInfo(AData);
    ZDATA:
      if FFileOpen and (FState = zrcData) then
      begin
        if (AData <> '') and not FSink.Write(@AData[1], Length(AData)) then
        begin
          Abort(zrError, rsZmWriteFailed);
          Exit;
        end;
        Inc(FPos, Length(AData));
        Inc(FTotal, Length(AData));
        if Assigned(FOnProgress) then
          FOnProgress(Self, FName, FPos, FSize, FTotal);
        if AEnd in [ZCRCQ, ZCRCW] then
          SendHex(ZACK, Cardinal(FPos));
        if AEnd in [ZCRCE, ZCRCW] then
          FState := zrcHeaders;          { the frame ends: a header comes next }
      end;
  end;
end;

procedure TZmReceiver.Cancelled(Sender: TObject);
begin
  if FFinishing then
    Exit;
  CloseFile(False);
  EndInInput(zrCancelledThere, rsZmCancelledThere);
end;

procedure TZmReceiver.Input(AData: PByte; ACount: Integer; ANowMs: Double);
var
  i: Integer;
begin
  FNow := ANowMs;
  i := 0;
  while (i < ACount) and not FDone do
  begin
    if FState = zrcWaitOO then
    begin
      { the sender's "OO", after the CR LF of its ZFIN we have not eaten yet }
      while (i < ACount) and (FOs = 0) and (FTailEaten < 3) and (AData[i] in [$0D, $8D, $0A, $8A, $11]) do
      begin
        Inc(i);
        Inc(FTailEaten);
      end;
      while (i < ACount) and (FOs < 2) and (AData[i] = Ord('O')) do
      begin
        Inc(i);
        Inc(FOs);
      end;
      if (FOs = 2) or (i < ACount) then
        Finish(zrOk, '', BytesAt(AData, i, ACount));
      Exit;
    end;
    Inc(i, FReader.Push(@AData[i], ACount - i));
    if FFinishing then
    begin
      Finish(FResult, FMessage, LeftoverOf(FResult, AData, i, ACount));
      Exit;
    end;
  end;
end;

procedure TZmReceiver.Tick(ANowMs: Double);
begin
  FNow := ANowMs;
  if FDone or (FState = zrcIdle) then
    Exit;
  if FState = zrcWaitOO then
  begin
    if FNow - FOStart >= OverAndOutMs then
      Finish(zrOk, '', '');
    Exit;
  end;
  if FNow - FLastActivity < FTimeoutMs then
    Exit;
  if FRetries >= FMaxRetries then
  begin
    Send(ZmAbortSequence);
    Finish(zrTimeout, rsZmTimeout, '');
    Exit;
  end;
  Inc(FRetries);
  FLastActivity := FNow;
  case FLast of
    zrkRinit: SendRinit;
    zrkRpos: Rpos;
  end;
end;

procedure TZmReceiver.Cancel;
begin
  if FDone then
    Exit;
  Send(ZmAbortSequence);
  Finish(zrCancelledHere, rsZmCancelledHere, '');
end;

{ ==== TZmSender =========================================================================== }

constructor TZmSender.Create(ASource: TZmFileSource);
begin
  inherited Create;
  FSource := ASource;
  FReader := TZmReader.Create;
  FReader.OnHeader := @Header;
  FReader.OnData := @Data;
  FReader.OnCancel := @Cancelled;
  FTimeoutMs := 10000;
  FMaxRetries := 10;
  SetLength(FBuf, ZmSendSubpacket);
end;

destructor TZmSender.Destroy;
begin
  FReader.Free;
  inherited Destroy;
end;

function TZmSender.GetUseCrc32: Boolean;
begin
  case FCrcMode of
    zcmCrc16: Result := False;
    zcmCrc32: Result := True;
  else
    Result := FCrc32;
  end;
end;

procedure TZmSender.SetUseCrc32(AValue: Boolean);
begin
  if AValue then FCrcMode := zcmCrc32 else FCrcMode := zcmCrc16;
end;

procedure TZmSender.Send(const AData: RawByteString);
begin
  if Assigned(FOnSend) then
    FOnSend(Self, AData);
end;

{ a header the other side must answer: kept to repeat on ZNAK or a timeout }
procedure TZmSender.SendLast(const AData: RawByteString);
begin
  FLastHeader := AData;
  FLastActivity := FNow;
  Send(AData);
end;

procedure TZmSender.Start(const AInit: TZmHeader; ANowMs: Double);
var
  f: Byte;
begin
  FNow := ANowMs;
  f := AInit.P[3];
  if FCrcMode = zcmAuto then
    FCrc32 := (f and CANFC32) <> 0
  else
    FCrc32 := FCrcMode = zcmCrc32;
  FEsc.Init((f and ESCCTL) <> 0);
  { buffer size in P0 / P1; 0 = the receiver takes a full stream }
  FBufSize := AInit.P[0] or (Integer(AInit.P[1]) shl 8);
  FLastActivity := FNow;
  NextFile;
end;

procedure TZmSender.NextFile;
var
  name: string;
  size, mtime: Int64;
  stream: TStream;
  fl: Integer;
  bl: Int64;
  info: RawByteString;
begin
  fl := FSource.FilesLeft;
  bl := FSource.BytesLeft;
  if not FSource.Next(name, size, mtime, stream) then
  begin
    FState := zsnFin;
    SendLast(ZmEncodeHexHeader(ZmPosHeader(ZFIN, 0)));
    Exit;
  end;
  FName := name;
  FSize := size;
  FMTime := mtime;
  FStream := stream;
  FPos := 0;
  FState := zsnFile;
  info := ZmBuildFileInfo(name, size, mtime, fl, bl);
  SendLast(ZmEncodeBinHeader(ZmFlagsHeader(ZFILE, ZCBIN, 0, 0, 0), FCrc32, FEsc)
    + ZmEncodeSubpacket(@info[1], Length(info), ZCRCW, FCrc32, FEsc));
end;

procedure TZmSender.StartData(APos: Int64);
begin
  if APos > FSize then
    APos := FSize;
  if APos < 0 then
    APos := 0;
  FPos := APos;
  FWindowStart := APos;
  if FStream <> nil then
    FStream.Position := APos;
  FState := zsnData;
  FLastHeader := '';
  Send(ZmEncodeBinHeader(ZmPosHeader(ZDATA, Cardinal(APos)), FCrc32, FEsc));
end;

{ as much data as CanSend allows now: 1 KB subpackets, ZCRCG while streaming, ZCRCW
  at the end of a window, ZCRCE and ZEOF at the end of the file }
procedure TZmSender.Pump;
var
  allow: Int64;
  n: Integer;
  e: Byte;
  s: RawByteString;
  last: Boolean;
begin
  if (FState <> zsnData) or FDone then
    Exit;
  { asked once a call: what the host takes now (its queue drains between calls) }
  if Assigned(FCanSend) then
  begin
    allow := FCanSend();
    if allow <= 0 then
      Exit;
  end
  else
    allow := High(Int64);
  begin
    while (FState = zsnData) and (allow > 0) do
    begin
      n := ZmSendSubpacket;
      if FSize - FPos < n then
        n := FSize - FPos;
      if (n > 0) and (FStream <> nil) then
        n := FStream.Read(FBuf[0], n);
      if n < 0 then
        n := 0;
      last := FPos + n >= FSize;
      if last then
        e := ZCRCE
      else if (FBufSize > 0) and (FPos + n - FWindowStart >= FBufSize) then
        e := ZCRCW
      else
        e := ZCRCG;
      if n > 0 then
        s := ZmEncodeSubpacket(@FBuf[0], n, e, FCrc32, FEsc)
      else
        s := ZmEncodeSubpacket(nil, 0, e, FCrc32, FEsc);
      Inc(FPos, n);
      Inc(FTotal, n);
      Dec(allow, Length(s));
      Send(s);
      if Assigned(FOnProgress) then
        FOnProgress(Self, FName, FPos, FSize, FTotal);
      if last then
      begin
        FState := zsnEof;
        SendLast(ZmEncodeBinHeader(ZmPosHeader(ZEOF, Cardinal(FSize)), FCrc32, FEsc));
      end
      else if e = ZCRCW then
      begin
        FState := zsnWaitAck;
        FLastActivity := FNow;
        FLastHeader := '';
      end;
    end;
  end;
end;

procedure TZmSender.EndInInput(AResult: TZmResult; const AMessage: string);
begin
  FFinishing := True;
  FResult := AResult;
  FMessage := AMessage;
  FReader.Stop;
end;

procedure TZmSender.Abort(AResult: TZmResult; const AMessage: string);
begin
  Send(ZmAbortSequence);
  EndInInput(AResult, AMessage);
end;

procedure TZmSender.Finish(AResult: TZmResult; const AMessage: string; const ALeftover: RawByteString);
begin
  if FDone then
    Exit;
  FDone := True;
  FState := zsnDone;
  if Assigned(FOnDone) then
    FOnDone(Self, AResult, AMessage, ALeftover);
end;

procedure TZmSender.Header(const AHeader: TZmHeader; AKind: TZmHeaderKind);
var
  pos: Int64;
begin
  if FFinishing then
    Exit;
  FLastActivity := FNow;
  FRetries := 0;
  pos := ZmHeaderPos(AHeader);
  case AHeader.FrameType of
    ZRPOS:
      if FState in [zsnFile, zsnData, zsnWaitAck, zsnEof] then
      begin
        if FState <> zsnFile then
          Inc(FRepositions);
        StartData(pos);
      end;
    ZSKIP:
      if FState in [zsnFile, zsnData, zsnWaitAck, zsnEof] then
        NextFile;
    ZRINIT:
      { after ZEOF: the file is whole. After ZFIN: our ZFIN went missing, again. Elsewhere
        (rz says it twice at the start): not an answer to anything we sent }
      if FState = zsnEof then
      begin
        Inc(FFiles);
        NextFile;
      end
      else if FState = zsnFin then
        Send(FLastHeader);
    ZACK:
      if FState = zsnWaitAck then
        StartData(pos);                  { a new frame at the acknowledged place }
    ZNAK:
      if FLastHeader <> '' then
        Send(FLastHeader);
    ZFIN:
      if FState = zsnFin then
      begin
        Send('OO');
        EndInInput(zrOk, '');
      end;
    ZCAN, ZABORT:
      EndInInput(zrCancelledThere, rsZmCancelledThere);
    ZFERR:
      EndInInput(zrError, rsZmFileError);
  end;
end;

procedure TZmSender.Data(const AData: RawByteString; AEnd: Byte; ACrcOk: Boolean);
begin
  { a receiver sends no data; a ZSINIT-like header's subpacket is read and dropped }
end;

procedure TZmSender.Cancelled(Sender: TObject);
begin
  if not FFinishing then
    EndInInput(zrCancelledThere, rsZmCancelledThere);
end;

procedure TZmSender.Input(AData: PByte; ACount: Integer; ANowMs: Double);
var
  i: Integer;
begin
  FNow := ANowMs;
  i := 0;
  while (i < ACount) and not FDone do
  begin
    Inc(i, FReader.Push(@AData[i], ACount - i));
    if FFinishing then
    begin
      Finish(FResult, FMessage, LeftoverOf(FResult, AData, i, ACount));
      Exit;
    end;
  end;
  Pump;
end;

procedure TZmSender.Tick(ANowMs: Double);
begin
  FNow := ANowMs;
  if FDone or (FState = zsnIdle) then
    Exit;
  if FState = zsnData then
  begin
    Pump;
    Exit;
  end;
  if FNow - FLastActivity < FTimeoutMs then
    Exit;
  if (FState = zsnFin) and (FRetries >= FinRetries) then
  begin
    { every file was acknowledged; the receiver's ZFIN does not come (it may have gone
      already): done, as sz is }
    Finish(zrOk, '', '');
    Exit;
  end;
  if FRetries >= FMaxRetries then
  begin
    Send(ZmAbortSequence);
    Finish(zrTimeout, rsZmTimeout, '');
    Exit;
  end;
  Inc(FRetries);
  FLastActivity := FNow;
  if FLastHeader <> '' then
    Send(FLastHeader)
  else if FState = zsnWaitAck then
    { the ZACK did not come: the window again from its start }
    StartData(FWindowStart);
end;

procedure TZmSender.Cancel;
begin
  if FDone then
    Exit;
  Send(ZmAbortSequence);
  Finish(zrCancelledHere, rsZmCancelledHere, '');
end;

end.
