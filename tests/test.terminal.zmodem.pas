unit test.terminal.zmodem;
{$mode objfpc}{$H+}
{ The terminal example's ZMODEM (7 期, spec 19.7): uzmodem (CRCs, escaping, headers,
  subpackets, the frame reader, the file information block), uzmodemsession (the
  receiver and sender state machines: lrzsz's own recorded bytes replayed, loopback,
  fault injection, timeouts) and uzmodemterm (the terminal glue on a real core).

  The expected bytes are standard check values and what lrzsz 0.12.21rc sent on the
  wire (spec 19.2 item 11, tests/fixtures/terminal-zmodem/); no expected value comes
  from our own encoder. Z1-Z14, S1-S9 and T1-T8 of the phase 7 plan. }

interface

uses
  Classes, SysUtils, fpcunit, testregistry, uzmodem;

type
  TTyTerminalZmodemTests = class(TTestCase)
  published
    { Task 6: frames }
    procedure TestCrc16CheckValue;                           { Z1 }
    procedure TestCrc32CheckValue;                           { Z2 }
    procedure TestTheZrinitRzSends;                          { Z3 }
    procedure TestTheZrqinitSzSends;                         { Z4 }
    procedure TestZfinAndZackHaveNoXon;                      { Z5 }
    procedure TestTheDefaultEscapes;                         { Z6 }
    procedure TestEscapingEveryControl;                      { Z7 }
    procedure TestCrAfterAtIsEscaped;                        { Z8 }
    procedure TestHeadersAmongGarbage;                       { Z9 }
    procedure TestDataSubpackets;                            { Z10 }
    procedure TestUnescapedXonXoffAreDropped;                { Z11 }
    procedure TestFiveCansAbort;                             { Z12 }
    procedure TestAnOverlongSubpacket;                       { Z13 }
    procedure TestTheFileInformation;                        { Z14 }
    { Task 7: the state machines }
    procedure TestReceivingWhatSzSent;                       { S1 }
    procedure TestSendingToWhatRzSaid;                       { S2 }
    procedure TestLoopback;                                  { S3 }
    procedure TestLoopbackWithFaults;                        { S4 }
    procedure TestTheReceiverTimesOut;                       { S5 }
    procedure TestCancelling;                                { S6 }
    procedure TestOverAndOut;                                { S7 }
    procedure TestZcommandIsRefused;                         { S8 }
    procedure TestAZeofAtTheWrongPlace;                      { S9 }
    { found against the real lrzsz (Task 13): sz -e's hex ZSINIT carries a subpacket;
      rz gives up after about 40 KB of garbage, so an upload keeps a window }
    procedure TestAHexZsinitIsAnswered;                      { S10 }
    procedure TestTheSendersWindow;                          { S11 }
    { the phase 7 review's fixes }
    procedure TestAnUploadWithNoRoomTimesOut;
    procedure TestAFileThatEndsEarlyFails;
    procedure TestA4GiBFileIsSkipped;
    procedure TestA4GiBFileInTheTerminal;
    procedure TestDecliningShowsWhatFollowed;
    procedure TestEveryDeviceNameIsRenamed;
    procedure TestALongNameIsCut;
    procedure TestAZeofRepeatedAfterTheFileIsAnsweredAgain;
    { Task 8: the terminal glue }
    procedure TestSafeFileNames;
    procedure TestUniqueFileNames;
    procedure TestDetection;                                 { T1 }
    procedure TestNothingIsSentBeforeTheAnswer;              { T2 }
    procedure TestAWholeDownload;                            { T3 }
    procedure TestProgressIsThrottled;                       { T4 }
    procedure TestFiveCtrlXCancel;                           { T5 }
    procedure TestRefusedBehindConPty;                       { T6 }
    procedure TestResetMidDownload;                          { T7 }
    procedure TestUploadIsThrottled;                         { T8 }
  end;

{ bytes as two-digit hex separated by spaces (failure messages) }
function ZmHex(const S: RawByteString): string;

implementation

uses
  Math, StrUtils, fpjson, md5, tyControls.Terminal.Buffer, tyControls.Terminal.Core, uzmodemsession,
  uzmodemterm, test.terminal.oracle;

{$IFDEF MSWINDOWS}
{ for a sparse file (FSCTL_SET_SPARSE): the Windows unit here would hide SysUtils' names }
function TyDeviceIoControl(hDevice: THandle; dwIoControlCode: LongWord; lpInBuffer: Pointer; nInBufferSize: LongWord;
  lpOutBuffer: Pointer; nOutBufferSize: LongWord; var lpBytesReturned: LongWord; lpOverlapped: Pointer): LongBool;
  stdcall; external 'kernel32' name 'DeviceIoControl';
{$ENDIF}

function ZmHex(const S: RawByteString): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do
  begin
    if i > 1 then Result := Result + ' ';
    Result := Result + IntToHex(Ord(S[i]), 2);
  end;
end;

function Cycle(ACount: Integer; AStart: Integer = 0): RawByteString;
var
  i: Integer;
begin
  Result := '';
  SetLength(Result, ACount);
  for i := 1 to ACount do
    Result[i] := AnsiChar((AStart + i - 1) and 255);
end;

type
  TReaderLog = class
  public
    Reader: TZmReader;
    Headers: array of TZmHeader;
    Kinds: array of TZmHeaderKind;
    Garbage: array of Integer;
    Data: array of RawByteString;
    Ends: array of Byte;
    Oks: array of Boolean;
    Cancels: Integer;
    constructor Create;
    destructor Destroy; override;
    procedure OnHeader(const AHeader: TZmHeader; AKind: TZmHeaderKind);
    procedure OnData(const AData: RawByteString; AEnd: Byte; ACrcOk: Boolean);
    procedure OnCancel(Sender: TObject);
    procedure PushAll(const S: RawByteString);
    procedure PushEach(const S: RawByteString);
  end;

constructor TReaderLog.Create;
begin
  inherited Create;
  Reader := TZmReader.Create;
  Reader.OnHeader := @OnHeader;
  Reader.OnData := @OnData;
  Reader.OnCancel := @OnCancel;
end;

destructor TReaderLog.Destroy;
begin
  Reader.Free;
  inherited Destroy;
end;

procedure TReaderLog.OnHeader(const AHeader: TZmHeader; AKind: TZmHeaderKind);
begin
  SetLength(Headers, Length(Headers) + 1);
  Headers[High(Headers)] := AHeader;
  SetLength(Kinds, Length(Kinds) + 1);
  Kinds[High(Kinds)] := AKind;
  SetLength(Garbage, Length(Garbage) + 1);
  Garbage[High(Garbage)] := Reader.GarbageCount;
end;

procedure TReaderLog.OnData(const AData: RawByteString; AEnd: Byte; ACrcOk: Boolean);
begin
  SetLength(Data, Length(Data) + 1);
  Data[High(Data)] := AData;
  SetLength(Ends, Length(Ends) + 1);
  Ends[High(Ends)] := AEnd;
  SetLength(Oks, Length(Oks) + 1);
  Oks[High(Oks)] := ACrcOk;
end;

procedure TReaderLog.OnCancel(Sender: TObject);
begin
  Inc(Cancels);
end;

procedure TReaderLog.PushAll(const S: RawByteString);
begin
  if S <> '' then
    Reader.Push(@S[1], Length(S));
end;

procedure TReaderLog.PushEach(const S: RawByteString);
var
  i: Integer;
begin
  for i := 1 to Length(S) do
    Reader.Push(@S[i], 1);
end;

{ ---- Task 6 ---------------------------------------------------------------------------- }

{ Z1. Mutation: the polynomial $8408. }
procedure TTyTerminalZmodemTests.TestCrc16CheckValue;
var
  s: RawByteString;
  c: Word;
begin
  s := '123456789';
  AssertEquals('CRC-16/XMODEM check value', $31C3, ZmCrc16(0, @s[1], 9));
  c := ZmCrc16(0, @s[1], 2);
  c := ZmCrc16(c, @s[3], 4);
  c := ZmCrc16(c, @s[7], 3);
  AssertEquals('in three parts', $31C3, c);
end;

{ Z2. Mutation: starting at 0. }
procedure TTyTerminalZmodemTests.TestCrc32CheckValue;
var
  s: RawByteString;
begin
  s := '123456789';
  AssertEquals('CRC-32 check value', Int64($CBF43926), Int64(not ZmCrc32($FFFFFFFF, @s[1], 9)));
end;

{ Z3 (rz on the wire). Mutations: upper-case hex; ZF0 in P[0]. }
procedure TTyTerminalZmodemTests.TestTheZrinitRzSends;
begin
  AssertEquals(ZmHex('**'#$18'B0100000023be50'#13#$8A#$11),
    ZmHex(ZmEncodeHexHeader(ZmFlagsHeader(ZRINIT, $23, 0, 0, 0))));
end;

{ Z4 (sz on the wire) }
procedure TTyTerminalZmodemTests.TestTheZrqinitSzSends;
begin
  AssertEquals(ZmHex('**'#$18'B00000000000000'#13#$8A#$11), ZmHex(ZmEncodeHexHeader(ZmPosHeader(ZRQINIT, 0))));
end;

{ Z5. Mutation: XON always. }
procedure TTyTerminalZmodemTests.TestZfinAndZackHaveNoXon;
begin
  AssertEquals('ZFIN', ZmHex('**'#$18'B0800000000022d'#13#$8A), ZmHex(ZmEncodeHexHeader(ZmPosHeader(ZFIN, 0))));
  AssertEquals('ZACK', ZmHex('**'#$18'B0300000000eed2'#13#$8A), ZmHex(ZmEncodeHexHeader(ZmPosHeader(ZACK, 0))));
  AssertEquals('ZRPOS keeps it', #$11, Copy(ZmEncodeHexHeader(ZmPosHeader(ZRPOS, 5)), 21, 1));
end;

{ Z6. Mutation: $18 left out. }
procedure TTyTerminalZmodemTests.TestTheDefaultEscapes;
var
  e: TZmEscaper;
  c: Integer;
  b: Byte;
  s: RawByteString;
  list: string;
begin
  list := '';
  for c := 0 to 255 do
  begin
    e.Init(False);
    b := c;
    s := e.Escape(@b, 1);
    if Length(s) = 2 then
    begin
      list := list + IntToHex(c, 2) + ' ';
      AssertEquals('ZDLE first', ZDLE, Ord(s[1]));
      AssertEquals('then c xor $40', c xor $40, Ord(s[2]));
    end
    else
      AssertEquals('as it is', c, Ord(s[1]));
  end;
  AssertEquals('exactly these', '10 11 13 18 90 91 93 ', list);
end;

{ Z7. Mutation: $7F counted as a control. }
procedure TTyTerminalZmodemTests.TestEscapingEveryControl;
var
  e: TZmEscaper;
  c, n: Integer;
  b: Byte;
  s: RawByteString;
begin
  n := 0;
  for c := 0 to 255 do
  begin
    e.Init(True);
    b := c;
    s := e.Escape(@b, 1);
    if Length(s) = 2 then
    begin
      Inc(n);
      AssertTrue(Format('%.2x is a control', [c]), (c and $60) = 0);
      AssertEquals(c xor $40, Ord(s[2]));
    end
    else
      AssertFalse(Format('%.2x left as it is', [c]), (c and $60) = 0);
  end;
  AssertEquals('64 controls', 64, n);
end;

{ Z8. Mutation: LastSent dropped. }
procedure TTyTerminalZmodemTests.TestCrAfterAtIsEscaped;
var
  e: TZmEscaper;
  s: RawByteString;
begin
  e.Init(False);
  s := '@'#13'@'#$8D'A'#13;
  AssertEquals(ZmHex('@'#$18#$4D'@'#$18#$CD'A'#13), ZmHex(e.Escape(@s[1], Length(s))));
end;

{ Z9. rz's prompt and random garbage (no '*', no CAN, no XON / XOFF), then the three
  headers of Z3-Z5, fed a byte at a time. }
procedure TTyTerminalZmodemTests.TestHeadersAmongGarbage;
var
  r: TReaderLog;
  s, junk: RawByteString;
  i: Integer;
  b: Byte;
begin
  RandSeed := 7;
  junk := '';
  i := 0;
  while i < 100 do
  begin
    b := Random(256);
    if b in [$2A, $18, $11, $13, $91, $93] then
      Continue;
    junk := junk + AnsiChar(b);
    Inc(i);
  end;
  s := 'rz'#13 + junk + '**'#$18'B0100000023be50'#13#$8A#$11 + '**'#$18'B00000000000000'#13#$8A#$11
    + '**'#$18'B0800000000022d'#13#$8A + '**'#$18'B0300000000eed2'#13#$8A;
  r := TReaderLog.Create;
  try
    r.PushEach(s);
    AssertEquals('four headers', 4, Length(r.Headers));
    AssertEquals('ZRINIT', ZRINIT, r.Headers[0].FrameType);
    AssertEquals('its ZF0', $23, r.Headers[0].P[3]);
    AssertEquals('ZRQINIT', ZRQINIT, r.Headers[1].FrameType);
    AssertEquals('ZFIN', ZFIN, r.Headers[2].FrameType);
    AssertEquals('ZACK', ZACK, r.Headers[3].FrameType);
    AssertTrue('hex', r.Kinds[0] = zhkHex);
    AssertEquals('the garbage before the first', 103, r.Garbage[0]);
    AssertEquals('none between them', 0, r.Garbage[1] + r.Garbage[2] + r.Garbage[3]);
  finally
    r.Free;
  end;
end;

function DataStream(out AFirstLen: Integer): RawByteString;
var
  e: TZmEscaper;
  d1, d2: RawByteString;
begin
  e.Init(False);
  d1 := Cycle(1024);
  d2 := 'x';
  Result := ZmEncodeBinHeader(ZmPosHeader(ZDATA, 0), True, e);
  AFirstLen := Length(Result);
  Result := Result + ZmEncodeSubpacket(@d1[1], 1024, ZCRCG, True, e)
    + ZmEncodeSubpacket(@d2[1], 1, ZCRCQ, True, e)
    + ZmEncodeSubpacket(nil, 0, ZCRCE, True, e);
end;

{ Z10. Mutation: ZRUB1 not unescaped (lrzsz does not send it; our reader must take it:
  the stream here is changed to carry it). }
procedure TTyTerminalZmodemTests.TestDataSubpackets;
var
  r: TReaderLog;
  s: RawByteString;
  hdr, k, pos: Integer;
  e: TZmEscaper;
  pass: Integer;
  head: RawByteString;
begin
  s := DataStream(hdr);
  for pass := 0 to 1 do
  begin
    r := TReaderLog.Create;
    try
      if pass = 0 then r.PushAll(s) else r.PushEach(s);
      AssertEquals('the header', 1, Length(r.Headers));
      AssertTrue('binary 32', r.Kinds[0] = zhkBin32);
      AssertEquals('ZDATA', ZDATA, r.Headers[0].FrameType);
      AssertEquals('three subpackets', 3, Length(r.Data));
      AssertTrue('the first, byte for byte', r.Data[0] = Cycle(1024));
      AssertEquals('ZCRCG', ZCRCG, r.Ends[0]);
      AssertTrue('the second', r.Data[1] = 'x');
      AssertEquals('ZCRCQ', ZCRCQ, r.Ends[1]);
      AssertEquals('the third is empty', 0, Length(r.Data[2]));
      AssertEquals('ZCRCE', ZCRCE, r.Ends[2]);
      AssertTrue('CRCs', r.Oks[0] and r.Oks[1] and r.Oks[2]);
      AssertFalse('back to headers', r.Reader.InData);
    finally
      r.Free;
    end;
  end;
  { one data byte changed (the byte 0x20 of the first subpacket, sent as it is) }
  e.Init(False);
  head := Cycle(32);
  pos := hdr + Length(e.Escape(@head[1], 32)) + 1;
  AssertEquals('the byte found', $20, Ord(s[pos]));
  s[pos] := 'Z';
  r := TReaderLog.Create;
  try
    r.PushAll(s);
    AssertFalse('that CRC is wrong', r.Oks[0]);
  finally
    r.Free;
  end;
  { ZRUB0 / ZRUB1 for $7F / $FF, as the spec allows }
  s := DataStream(hdr);
  k := PosEx(#$FF, s, hdr + 1);
  AssertTrue('a $FF sent as it is', k > hdr);
  s := Copy(s, 1, k - 1) + #$18 + AnsiChar(ZRUB1) + Copy(s, k + 1, MaxInt);
  k := PosEx(#$7F, s, hdr + 1);
  s := Copy(s, 1, k - 1) + #$18 + AnsiChar(ZRUB0) + Copy(s, k + 1, MaxInt);
  r := TReaderLog.Create;
  try
    r.PushAll(s);
    AssertTrue('the same data', r.Data[0] = Cycle(1024));
    AssertTrue('CRC right', r.Oks[0]);
  finally
    r.Free;
  end;
end;

{ Z11. Mutation: unescaped XON / XOFF kept. }
procedure TTyTerminalZmodemTests.TestUnescapedXonXoffAreDropped;
var
  r: TReaderLog;
  s: RawByteString;
  hdr, at: Integer;
begin
  s := DataStream(hdr);
  at := hdr + 100;
  s := Copy(s, 1, at) + #$11#$93 + Copy(s, at + 1, MaxInt);
  r := TReaderLog.Create;
  try
    r.PushAll(s);
    AssertTrue('the data without them', r.Data[0] = Cycle(1024));
    AssertTrue('CRC right', r.Oks[0]);
  finally
    r.Free;
  end;
end;

{ Z12. Mutation: the threshold 4. }
procedure TTyTerminalZmodemTests.TestFiveCansAbort;
var
  r: TReaderLog;
begin
  r := TReaderLog.Create;
  try
    r.PushAll(#$18#$18#$18#$18'x');
    AssertEquals('four: nothing', 0, r.Cancels);
    r.PushAll(#$18#$18#$18#$18#$18);
    AssertEquals('five', 1, r.Cancels);
  finally
    r.Free;
  end;
  r := TReaderLog.Create;
  try
    r.PushAll(ZmAbortSequence);
    AssertEquals('lrzsz''s abort once', 1, r.Cancels);
  finally
    r.Free;
  end;
end;

{ Z13. Mutation: no length limit. }
procedure TTyTerminalZmodemTests.TestAnOverlongSubpacket;
var
  r: TReaderLog;
  e: TZmEscaper;
  d, s: RawByteString;
begin
  e.Init(False);
  d := StringOfChar('A', 9000);
  s := ZmEncodeBinHeader(ZmPosHeader(ZDATA, 0), False, e) + ZmEncodeSubpacket(@d[1], 9000, ZCRCW, False, e)
    + ZmEncodeHexHeader(ZmPosHeader(ZEOF, 9000));
  r := TReaderLog.Create;
  try
    r.PushAll(s);
    AssertEquals('one subpacket, failed', 1, Length(r.Data));
    AssertFalse('as a CRC error', r.Oks[0]);
    AssertEquals('the next header', 2, Length(r.Headers));
    AssertEquals('ZEOF', ZEOF, r.Headers[1].FrameType);
    AssertEquals('its position', 9000, ZmHeaderPos(r.Headers[1]));
  finally
    r.Free;
  end;
end;

{ Z14. Mutation: the time read as decimal. }
procedure TTyTerminalZmodemTests.TestTheFileInformation;
var
  name: string;
  size, mtime: Int64;
  mode: Cardinal;
begin
  AssertTrue(ZmParseFileInfo('a b.bin'#0'1234 14530722433 100644 0 1 1234'#0, name, size, mtime, mode));
  AssertEquals('a b.bin', name);
  AssertEquals(1234, size);
  AssertEquals(Int64(&14530722433), mtime);
  AssertEquals(Int64(&100644), Int64(mode));
  AssertTrue('name and size only', ZmParseFileInfo('x'#0'5'#0, name, size, mtime, mode));
  AssertEquals(5, size);
  AssertEquals('no time', -1, mtime);
  AssertFalse('no size', ZmParseFileInfo('x'#0'abc'#0, name, size, mtime, mode));
  AssertFalse('no name', ZmParseFileInfo(#0'5'#0, name, size, mtime, mode));
  AssertTrue('ours reads back', ZmParseFileInfo(ZmBuildFileInfo('f.txt', 42, &17, 2, 100), name, size, mtime, mode));
  AssertEquals('f.txt', name);
  AssertEquals(42, size);
  AssertEquals(Int64(&17), mtime);
  AssertEquals(Int64(&100644), Int64(mode));
end;

{ ---- Task 7: the state machines ------------------------------------------------------------ }

type
  { files in memory; a file not finished whole is dropped (as the example deletes it) }
  TMemSink = class(TZmFileSink)
  public
    Names: TStringList;
    Contents: array of RawByteString;
    Complete: array of Boolean;
    Opens, Finishes, Incomplete: Integer;
    Refuse: string;                      { Open answers False for this name }
    Cur: RawByteString;
    constructor Create;
    destructor Destroy; override;
    function Open(const AName: string; ASize, AMTime: Int64): Boolean; override;
    function Write(AData: PByte; ACount: Integer): Boolean; override;
    procedure Finish(AComplete: Boolean); override;
  end;

  TMemSource = class(TZmFileSource)
  public
    Names: TStringList;
    Contents: array of RawByteString;
    Next_: Integer;
    Stream: TMemoryStream;
    LieSize: Int64;                      { > 0: every file says it is this long }
    constructor Create;
    destructor Destroy; override;
    procedure Add(const AName: string; const AData: RawByteString);
    function Next(out AName: string; out ASize, AMTime: Int64; out AStream: TStream): Boolean; override;
    function FilesLeft: Integer; override;
    function BytesLeft: Int64; override;
  end;

  { what a session did: its bytes out, how it ended }
  TZmLog = class
  public
    Sent: RawByteString;
    Limit: Integer;                      { > 0: more sent than this raises (a sender that does not stop) }
    Done: Boolean;
    Result_: TZmResult;
    Message: string;
    Leftover: RawByteString;
    procedure OnSend(Sender: TObject; const AData: RawByteString);
    procedure OnDone(Sender: TObject; AResult: TZmResult; const AMessage: string; const ALeftover: RawByteString);
  end;

  { a host's CanSend answering a fixed room }
  TRoom = class
  public
    Value: Integer;
    function Allow: Integer;
  end;

function TRoom.Allow: Integer;
begin
  Result := Value;
end;

constructor TMemSink.Create;
begin
  inherited Create;
  Names := TStringList.Create;
end;

destructor TMemSink.Destroy;
begin
  Names.Free;
  inherited Destroy;
end;

function TMemSink.Open(const AName: string; ASize, AMTime: Int64): Boolean;
begin
  Inc(Opens);
  if AName = Refuse then
    Exit(False);
  Cur := '';
  Names.Add(AName);
  Result := True;
end;

function TMemSink.Write(AData: PByte; ACount: Integer): Boolean;
var
  s: RawByteString;
begin
  s := '';
  SetLength(s, ACount);
  Move(AData^, s[1], ACount);
  Cur := Cur + s;
  Result := True;
end;

procedure TMemSink.Finish(AComplete: Boolean);
begin
  Inc(Finishes);
  SetLength(Contents, Length(Contents) + 1);
  Contents[High(Contents)] := Cur;
  SetLength(Complete, Length(Complete) + 1);
  Complete[High(Complete)] := AComplete;
  if not AComplete then
    Inc(Incomplete);
  Cur := '';
end;

constructor TMemSource.Create;
begin
  inherited Create;
  Names := TStringList.Create;
end;

destructor TMemSource.Destroy;
begin
  Stream.Free;
  Names.Free;
  inherited Destroy;
end;

procedure TMemSource.Add(const AName: string; const AData: RawByteString);
begin
  Names.Add(AName);
  SetLength(Contents, Length(Contents) + 1);
  Contents[High(Contents)] := AData;
end;

function TMemSource.Next(out AName: string; out ASize, AMTime: Int64; out AStream: TStream): Boolean;
begin
  AStream := nil;
  AName := '';
  ASize := 0;
  AMTime := 0;
  if Next_ >= Names.Count then
    Exit(False);
  FreeAndNil(Stream);
  Stream := TMemoryStream.Create;
  if Contents[Next_] <> '' then
    Stream.WriteBuffer(Contents[Next_][1], Length(Contents[Next_]));
  Stream.Position := 0;
  AName := Names[Next_];
  ASize := Length(Contents[Next_]);
  if LieSize > 0 then
    ASize := LieSize;
  AMTime := 1700000000;
  AStream := Stream;
  Inc(Next_);
  Result := True;
end;

function TMemSource.FilesLeft: Integer;
begin
  Result := Names.Count - Next_;
end;

function TMemSource.BytesLeft: Int64;
var
  i: Integer;
begin
  Result := 0;
  for i := Next_ to High(Contents) do
    Inc(Result, Length(Contents[i]));
end;

procedure TZmLog.OnSend(Sender: TObject; const AData: RawByteString);
begin
  Sent := Sent + AData;
  if (Limit > 0) and (Length(Sent) > Limit) then
    raise Exception.CreateFmt('more than %d bytes sent: the sender does not stop', [Limit]);
end;

procedure TZmLog.OnDone(Sender: TObject; AResult: TZmResult; const AMessage: string; const ALeftover: RawByteString);
begin
  Done := True;
  Result_ := AResult;
  Message := AMessage;
  Leftover := ALeftover;
end;

function ZmFixture(const AName: string): string;
begin
  Result := TyTermFixturePath('terminal-zmodem' + PathDelim + AName);
end;

function ReadBytes(const APath: string): RawByteString;
var
  f: TFileStream;
begin
  f := TFileStream.Create(APath, fmOpenRead or fmShareDenyWrite);
  try
    Result := '';
    SetLength(Result, f.Size);
    if f.Size > 0 then
      f.ReadBuffer(Result[1], f.Size);
  finally
    f.Free;
  end;
end;

function LoadCases: TJSONObject;
var
  s: RawByteString;
begin
  s := ReadBytes(ZmFixture('cases.json'));
  Result := GetJSON(s) as TJSONObject;
end;

type
  { every header in a byte stream, with the offset just past it }
  THeaderList = class
  public
    Reader: TZmReader;
    Types, Positions, Ends: array of Integer;
    Headers: array of TZmHeader;
    At: Integer;
    constructor Create(const S: RawByteString);
    destructor Destroy; override;
    procedure OnHeader(const AHeader: TZmHeader; AKind: TZmHeaderKind);
    { ZRINIT / ZRPOS repeated back to back (the other side's timing), each run as one }
    function Deduped: string;
  end;

constructor THeaderList.Create(const S: RawByteString);
var
  i: Integer;
begin
  inherited Create;
  Reader := TZmReader.Create;
  Reader.OnHeader := @OnHeader;
  for i := 1 to Length(S) do
  begin
    At := i;
    Reader.Push(@S[i], 1);
  end;
end;

destructor THeaderList.Destroy;
begin
  Reader.Free;
  inherited Destroy;
end;

procedure THeaderList.OnHeader(const AHeader: TZmHeader; AKind: TZmHeaderKind);
var
  n: Integer;
begin
  n := Length(Types);
  SetLength(Types, n + 1);
  SetLength(Positions, n + 1);
  SetLength(Ends, n + 1);
  SetLength(Headers, n + 1);
  Types[n] := AHeader.FrameType;
  Positions[n] := Integer(ZmHeaderPos(AHeader));
  Ends[n] := At;
  Headers[n] := AHeader;
end;

function THeaderList.Deduped: string;
var
  i: Integer;
  cur, prev: string;
begin
  Result := '';
  prev := '';
  for i := 0 to High(Types) do
  begin
    cur := ZmFrameName(Types[i]) + '@' + IntToStr(Positions[i]);
    if (cur = prev) and (Types[i] in [ZRINIT, ZRPOS]) then
      Continue;
    Result := Result + cur + ' ';
    prev := cur;
  end;
end;

{ S1. Mutation: the receiver answering ZFILE with ZRINIT instead of ZRPOS. Every
  recording, fed whole, a byte and seven bytes at a time. }
procedure TTyTerminalZmodemTests.TestReceivingWhatSzSent;
const
  Steps: array[0..2] of Integer = (0, 1, 7);
var
  cases, files: TJSONArray;
  doc, c, f: TJSONObject;
  k, j, si, step, p, n: Integer;
  sz, rz, want: RawByteString;
  sink: TMemSink;
  log: TZmLog;
  r: TZmReceiver;
  ours, theirs: THeaderList;
  id: string;
begin
  doc := LoadCases;
  try
    cases := doc.Arrays['cases'];
    AssertTrue('seven recordings', cases.Count >= 7);
    AssertEquals('lrzsz''s version', 'sz (lrzsz) 0.12.21rc', doc.Strings['sz']);
    for k := 0 to cases.Count - 1 do
    begin
      c := cases.Objects[k];
      id := c.Strings['id'];
      files := c.Arrays['files'];
      sz := ReadBytes(ZmFixture(id + '.sz.bin'));
      rz := ReadBytes(ZmFixture(id + '.rz.bin'));
      for si := 0 to 2 do
      begin
        step := Steps[si];
        sink := TMemSink.Create;
        log := TZmLog.Create;
        r := TZmReceiver.Create(sink);
        try
          r.OnSend := @log.OnSend;
          r.OnDone := @log.OnDone;
          { rz -e asked for every control character escaped: so do we, as rz did }
          r.EscapeControl := Pos('"-e"', c.Arrays['rzOptions'].AsJSON) > 0;
          r.Start(0);
          if step = 0 then
            r.Input(@sz[1], Length(sz), 0)
          else
          begin
            p := 1;
            while (p <= Length(sz)) and not r.Done do
            begin
              n := Min(step, Length(sz) - p + 1);
              r.Input(@sz[p], n, 0);
              Inc(p, n);
            end;
          end;
          AssertTrue(Format('%s/%d: done', [id, step]), log.Done);
          AssertTrue(Format('%s/%d: ok (%s)', [id, step, log.Message]), log.Result_ = zrOk);
          AssertEquals(Format('%s/%d: nothing after OO', [id, step]), '', ZmHex(log.Leftover));
          AssertEquals(Format('%s/%d: files', [id, step]), files.Count, sink.Names.Count);
          for j := 0 to files.Count - 1 do
          begin
            f := files.Objects[j];
            want := ReadBytes(ZmFixture(f.Strings['source']));
            AssertEquals(Format('%s/%d: name %d', [id, step, j]), f.Strings['name'], sink.Names[j]);
            AssertTrue(Format('%s/%d: file %d whole', [id, step, j]), sink.Complete[j]);
            AssertEquals(Format('%s/%d: size %d', [id, step, j]), Length(want), Length(sink.Contents[j]));
            AssertTrue(Format('%s/%d: content %d', [id, step, j]), sink.Contents[j] = want);
            AssertEquals(Format('%s/%d: md5 %d', [id, step, j]), f.Strings['md5'],
              MD5Print(MD5String(sink.Contents[j])));
          end;
          ours := THeaderList.Create(log.Sent);
          theirs := THeaderList.Create(rz);
          try
            AssertEquals(Format('%s/%d: our answers are rz''s', [id, step]), theirs.Deduped, ours.Deduped);
          finally
            ours.Free;
            theirs.Free;
          end;
        finally
          r.Free;
          log.Free;
          sink.Free;
        end;
      end;
    end;
  finally
    doc.Free;
  end;
end;

type
  { a stream of ZMODEM from a sender, decoded: the files it carries }
  TSentFiles = class
  public
    Reader: TZmReader;
    Last: Integer;
    Names: TStringList;
    Contents: array of RawByteString;
    Eofs: array of Int64;                  { the position each ZEOF names }
    Cur: RawByteString;
    Pos_: Integer;
    constructor Create(const S: RawByteString);
    destructor Destroy; override;
    procedure OnHeader(const AHeader: TZmHeader; AKind: TZmHeaderKind);
    procedure OnData(const AData: RawByteString; AEnd: Byte; ACrcOk: Boolean);
  end;

constructor TSentFiles.Create(const S: RawByteString);
begin
  inherited Create;
  Names := TStringList.Create;
  Reader := TZmReader.Create;
  Reader.OnHeader := @OnHeader;
  Reader.OnData := @OnData;
  if S <> '' then
    Reader.Push(@S[1], Length(S));
end;

destructor TSentFiles.Destroy;
begin
  Reader.Free;
  Names.Free;
  inherited Destroy;
end;

procedure TSentFiles.OnHeader(const AHeader: TZmHeader; AKind: TZmHeaderKind);
begin
  Last := AHeader.FrameType;
  case Last of
    ZDATA:
      begin
        Pos_ := ZmHeaderPos(AHeader);
        Cur := Copy(Cur, 1, Pos_);
      end;
    ZEOF:
      if Length(Contents) > 0 then
      begin
        Contents[High(Contents)] := Cur;
        SetLength(Eofs, Length(Contents));
        Eofs[High(Eofs)] := ZmHeaderPos(AHeader);
      end;
  end;
end;

procedure TSentFiles.OnData(const AData: RawByteString; AEnd: Byte; ACrcOk: Boolean);
var
  name: string;
  size, mtime: Int64;
  mode: Cardinal;
begin
  if not ACrcOk then
    raise Exception.Create('a bad CRC in what the sender sent');
  if Last = ZFILE then
  begin
    if ZmParseFileInfo(AData, name, size, mtime, mode) then
    begin
      Names.Add(name + '|' + IntToStr(size) + '|' + IntToStr(mtime));
      SetLength(Contents, Length(Contents) + 1);
      Cur := '';
    end;
  end
  else if Last = ZDATA then
    Cur := Cur + AData;
end;

{ S2. Mutation: ZEOF at one byte less than was sent. rz's headers from each recording
  fed one by one, each after the sender has answered the one before. }
procedure TTyTerminalZmodemTests.TestSendingToWhatRzSaid;
var
  cases, files: TJSONArray;
  doc, c: TJSONObject;
  k, j, from: Integer;
  rz, chunk: RawByteString;
  src: TMemSource;
  log: TZmLog;
  s: TZmSender;
  heads: THeaderList;
  got: TSentFiles;
  id: string;
begin
  doc := LoadCases;
  try
    cases := doc.Arrays['cases'];
    for k := 0 to cases.Count - 1 do
    begin
      c := cases.Objects[k];
      id := c.Strings['id'];
      files := c.Arrays['files'];
      rz := ReadBytes(ZmFixture(id + '.rz.bin'));
      src := TMemSource.Create;
      log := TZmLog.Create;
      s := TZmSender.Create(src);
      heads := THeaderList.Create(rz);
      try
        for j := 0 to files.Count - 1 do
          src.Add(files.Objects[j].Strings['name'], ReadBytes(ZmFixture(files.Objects[j].Strings['source'])));
        s.OnSend := @log.OnSend;
        s.OnDone := @log.OnDone;
        AssertEquals(id + ': rz starts with ZRINIT', ZRINIT, heads.Types[0]);
        s.Start(heads.Headers[0], 0);
        from := heads.Ends[0] + 1;
        for j := 1 to High(heads.Types) do
        begin
          if j < High(heads.Types) then
            chunk := Copy(rz, from, heads.Ends[j] - from + 1)
          else
            chunk := Copy(rz, from, MaxInt);
          from := heads.Ends[j] + 1;
          if chunk <> '' then
            s.Input(@chunk[1], Length(chunk), 0);
        end;
        AssertTrue(id + ': done', log.Done);
        AssertTrue(id + ': ok ' + log.Message, log.Result_ = zrOk);
        AssertEquals(id + ': OO last', 'OO', Copy(log.Sent, Length(log.Sent) - 1, 2));
        got := TSentFiles.Create(log.Sent);
        try
          AssertEquals(id + ': files', files.Count, got.Names.Count);
          for j := 0 to files.Count - 1 do
          begin
            AssertEquals(id + ': name, size, time', files.Objects[j].Strings['name'] + '|'
              + IntToStr(files.Objects[j].Integers['size']) + '|1700000000', got.Names[j]);
            AssertTrue(id + ': content ' + IntToStr(j), got.Contents[j] = src.Contents[j]);
            AssertTrue(id + ': a ZEOF for ' + IntToStr(j), j < Length(got.Eofs));
            AssertEquals(id + ': ZEOF at the size ' + IntToStr(j),
              files.Objects[j].Integers['size'], got.Eofs[j]);
          end;
        finally
          got.Free;
        end;
      finally
        heads.Free;
        s.Free;
        log.Free;
        src.Free;
      end;
    end;
  finally
    doc.Free;
  end;
end;

type
  { a sender and a receiver wired through two queues, optionally damaging bytes }
  TLoop = class
  public
    Sender: TZmSender;
    Receiver: TZmReceiver;
    Sink: TMemSink;
    Source: TMemSource;
    ToReceiver, ToSender: RawByteString;
    SLog, RLog: TZmLog;
    Now_: Double;
    Rnd: Cardinal;
    FlipEvery, DropEvery: Integer;   { 0 = never; else about one in this many bytes }
    Damaged: Integer;
    constructor Create;
    destructor Destroy; override;
    function NextRandom: Cardinal;
    function Damage(const S: RawByteString): RawByteString;
    procedure FromSender(Sender_: TObject; const AData: RawByteString);
    procedure FromReceiver(Sender_: TObject; const AData: RawByteString);
    procedure SenderDone(Sender_: TObject; AResult: TZmResult; const AMessage: string; const ALeftover: RawByteString);
    procedure ReceiverDone(Sender_: TObject; AResult: TZmResult; const AMessage: string; const ALeftover: RawByteString);
    procedure Run(const AInit: TZmHeader);
  end;

constructor TLoop.Create;
begin
  inherited Create;
  Sink := TMemSink.Create;
  Source := TMemSource.Create;
  SLog := TZmLog.Create;
  RLog := TZmLog.Create;
  Sender := TZmSender.Create(Source);
  Receiver := TZmReceiver.Create(Sink);
  Sender.OnSend := @FromSender;
  Receiver.OnSend := @FromReceiver;
  Sender.OnDone := @SenderDone;
  Receiver.OnDone := @ReceiverDone;
end;

destructor TLoop.Destroy;
begin
  Sender.Free;
  Receiver.Free;
  Sink.Free;
  Source.Free;
  SLog.Free;
  RLog.Free;
  inherited Destroy;
end;

{ xorshift32: the same damage for the same seed on every machine }
function TLoop.NextRandom: Cardinal;
begin
  Rnd := Rnd xor (Rnd shl 13);
  Rnd := Rnd xor (Rnd shr 17);
  Rnd := Rnd xor (Rnd shl 5);
  Result := Rnd;
end;

function TLoop.Damage(const S: RawByteString): RawByteString;
var
  i: Integer;
begin
  if (FlipEvery = 0) and (DropEvery = 0) then
    Exit(S);
  Result := '';
  for i := 1 to Length(S) do
  begin
    if (DropEvery > 0) and (NextRandom mod Cardinal(DropEvery) = 0) then
    begin
      Inc(Damaged);
      Continue;
    end;
    if (FlipEvery > 0) and (NextRandom mod Cardinal(FlipEvery) = 0) then
    begin
      Inc(Damaged);
      Result := Result + AnsiChar(Ord(S[i]) xor (1 shl (NextRandom mod 8)));
    end
    else
      Result := Result + S[i];
  end;
end;

procedure TLoop.FromSender(Sender_: TObject; const AData: RawByteString);
begin
  ToReceiver := ToReceiver + Damage(AData);
  if AData = 'OO' then
    ToReceiver := ToReceiver + 'TAIL';
end;

procedure TLoop.FromReceiver(Sender_: TObject; const AData: RawByteString);
begin
  ToSender := ToSender + Damage(AData);
  if AData = ZmEncodeHexHeader(ZmPosHeader(ZFIN, 0)) then
    ToSender := ToSender + 'TAIL';
end;

procedure TLoop.SenderDone(Sender_: TObject; AResult: TZmResult; const AMessage: string; const ALeftover: RawByteString);
begin
  SLog.OnDone(Sender_, AResult, AMessage, ALeftover);
end;

procedure TLoop.ReceiverDone(Sender_: TObject; AResult: TZmResult; const AMessage: string; const ALeftover: RawByteString);
begin
  RLog.OnDone(Sender_, AResult, AMessage, ALeftover);
end;

procedure TLoop.Run(const AInit: TZmHeader);
var
  s: RawByteString;
  guard: Integer;
begin
  Receiver.Start(Now_);
  Sender.Start(AInit, Now_);
  guard := 0;
  while not (SLog.Done and RLog.Done) do
  begin
    Inc(guard);
    if guard > 200000 then
      raise Exception.Create('the loop does not end');
    if ToReceiver <> '' then
    begin
      s := ToReceiver;
      ToReceiver := '';
      if not Receiver.Done then
        Receiver.Input(@s[1], Length(s), Now_);
    end
    else if ToSender <> '' then
    begin
      s := ToSender;
      ToSender := '';
      if not Sender.Done then
        Sender.Input(@s[1], Length(s), Now_);
    end
    else
    begin
      { nothing on the wire: time passes }
      Now_ := Now_ + 10001;
      Receiver.Tick(Now_);
      Sender.Tick(Now_);
    end;
  end;
end;

function InitHeader(ABuffer: Integer): TZmHeader;
begin
  Result := ZmFlagsHeader(ZRINIT, CANFDX or CANOVIO or CANFC32, 0, (ABuffer shr 8) and $FF, ABuffer and $FF);
end;

{ S3. Mutation: no ZRPOS after a bad CRC (S4 needs it; here: the loop must simply
  work in every option). }
procedure TTyTerminalZmodemTests.TestLoopback;
const
  Sizes: array[0..6] of Integer = (0, 1, 1023, 1024, 1025, 70000, 5000);
var
  combo, k, i: Integer;
  lp: TLoop;
  data: RawByteString;
  tag: string;
begin
  for combo := 0 to 4 do
    for k := 0 to High(Sizes) do
    begin
      if k = 6 then
        data := Cycle(Sizes[k])          { every byte value, the escaped ones many times }
      else
      begin
        RandSeed := k + 100;
        data := '';
        SetLength(data, Sizes[k]);
        for i := 1 to Sizes[k] do
          data[i] := AnsiChar(Random(256));
      end;
      lp := TLoop.Create;
      try
        lp.Source.Add('f' + IntToStr(k) + '.bin', data);
        case combo of
          1: lp.Sender.UseCrc32 := False;
          2: lp.Receiver.EscapeControl := True;
          3: lp.Receiver.MaxSubpacket := 1024;
        end;
        if combo = 4 then
          lp.Run(InitHeader(4096))
        else if combo = 2 then
          lp.Run(ZmFlagsHeader(ZRINIT, CANFDX or CANOVIO or CANFC32 or ESCCTL, 0, 0, 0))
        else
          lp.Run(InitHeader(0));
        tag := Format('combo %d size %d', [combo, Sizes[k]]);
        AssertTrue(tag + ': sender ok ' + lp.SLog.Message, lp.SLog.Result_ = zrOk);
        AssertTrue(tag + ': receiver ok ' + lp.RLog.Message, lp.RLog.Result_ = zrOk);
        AssertEquals(tag + ': one file', 1, Length(lp.Sink.Contents));
        AssertTrue(tag + ': whole', lp.Sink.Complete[0]);
        AssertTrue(tag + ': the same bytes', lp.Sink.Contents[0] = data);
        AssertEquals(tag + ': the receiver''s leftover', 'TAIL', lp.RLog.Leftover);
        AssertEquals(tag + ': the sender''s leftover', 'TAIL', lp.SLog.Leftover);
      finally
        lp.Free;
      end;
    end;
end;

{ S4. Mutation: the sender not going back on a ZRPOS mid-file. }
procedure TTyTerminalZmodemTests.TestLoopbackWithFaults;
var
  seed, i: Integer;
  lp: TLoop;
  data: RawByteString;
  retries, damaged: Integer;
begin
  data := '';
  SetLength(data, 70000);
  RandSeed := 42;
  for i := 1 to 70000 do
    data[i] := AnsiChar(Random(256));
  retries := 0;
  damaged := 0;
  for seed := 1 to 20 do
  begin
    lp := TLoop.Create;
    try
      lp.Rnd := Cardinal(seed) * 2654435761;
      lp.FlipEvery := 5000;
      lp.DropEvery := 20000;
      lp.Source.Add('r.bin', data);
      lp.Run(InitHeader(0));
      AssertTrue(Format('seed %d: sender ok (%s)', [seed, lp.SLog.Message]), lp.SLog.Result_ = zrOk);
      AssertTrue(Format('seed %d: receiver ok (%s)', [seed, lp.RLog.Message]), lp.RLog.Result_ = zrOk);
      AssertTrue(Format('seed %d: the same bytes', [seed]), (Length(lp.Sink.Contents) >= 1)
        and (lp.Sink.Contents[High(lp.Sink.Contents)] = data));
      Inc(retries, lp.Sender.Repositions + lp.Receiver.Errors);
      Inc(damaged, lp.Damaged);
    finally
      lp.Free;
    end;
  end;
  WriteLn(Format('zmodem faults: %d bytes damaged, %d repositions / errors', [damaged, retries]));
  AssertTrue('bytes were damaged', damaged > 0);
  AssertTrue('and recovered from', retries > 0);
end;

{ S5. Mutation: the retry count not reset by a header. }
procedure TTyTerminalZmodemTests.TestTheReceiverTimesOut;
var
  sink: TMemSink;
  log: TZmLog;
  r: TZmReceiver;
  t: Double;
  i: Integer;
  rinit, rq: RawByteString;
begin
  rinit := ZmEncodeHexHeader(ZmFlagsHeader(ZRINIT, CANFDX or CANOVIO or CANFC32, 0, 0, 0));
  rq := ZmEncodeHexHeader(ZmPosHeader(ZRQINIT, 0));
  sink := TMemSink.Create;
  log := TZmLog.Create;
  r := TZmReceiver.Create(sink);
  try
    r.OnSend := @log.OnSend;
    r.OnDone := @log.OnDone;
    r.Start(0);
    AssertTrue('ZRINIT first', log.Sent = rinit);
    t := 0;
    for i := 1 to 5 do
    begin
      log.Sent := '';
      t := t + 10001;
      r.Tick(t);
      AssertTrue(Format('repeat %d', [i]), log.Sent = rinit);
    end;
    { a header from the other side: the count starts again }
    r.Input(@rq[1], Length(rq), t);
    for i := 1 to 10 do
    begin
      log.Sent := '';
      t := t + 10001;
      r.Tick(t);
      AssertTrue(Format('after the header, repeat %d', [i]), log.Sent = rinit);
      AssertFalse('not done yet', log.Done);
    end;
    log.Sent := '';
    t := t + 10001;
    r.Tick(t);
    AssertEquals('the eleventh: the abort', ZmHex(ZmAbortSequence), ZmHex(log.Sent));
    AssertTrue('done', log.Done);
    AssertTrue('timed out', log.Result_ = zrTimeout);
  finally
    r.Free;
    log.Free;
    sink.Free;
  end;
end;

{ a ZFILE with its information, as a sender sends it }
function ZfileFrame(const AName: string; ASize: Int64): RawByteString;
var
  e: TZmEscaper;
  info: RawByteString;
begin
  e.Init(False);
  info := ZmBuildFileInfo(AName, ASize, 1700000000, 1, ASize);
  Result := ZmEncodeBinHeader(ZmFlagsHeader(ZFILE, ZCBIN, 0, 0, 0), True, e)
    + ZmEncodeSubpacket(@info[1], Length(info), ZCRCW, True, e);
end;

function ZdataFrame(APos: Integer; const AData: RawByteString; AEnd: Byte): RawByteString;
var
  e: TZmEscaper;
begin
  e.Init(False);
  Result := ZmEncodeBinHeader(ZmPosHeader(ZDATA, APos), True, e);
  if AData <> '' then
    Result := Result + ZmEncodeSubpacket(@AData[1], Length(AData), AEnd, True, e)
  else
    Result := Result + ZmEncodeSubpacket(nil, 0, AEnd, True, e);
end;

procedure FeedR(r: TZmReceiver; const S: RawByteString);
begin
  if S <> '' then
    r.Input(@S[1], Length(S), 0);
end;

{ S6: byte values }
procedure TTyTerminalZmodemTests.TestCancelling;
var
  sink: TMemSink;
  log: TZmLog;
  r: TZmReceiver;
begin
  sink := TMemSink.Create;
  log := TZmLog.Create;
  r := TZmReceiver.Create(sink);
  try
    r.OnSend := @log.OnSend;
    r.OnDone := @log.OnDone;
    r.Start(0);
    FeedR(r, ZfileFrame('half.bin', 5000) + ZdataFrame(0, Cycle(1000), ZCRCG));
    AssertEquals('opened', 1, sink.Opens);
    log.Sent := '';
    r.Cancel;
    AssertEquals('ten CAN, ten BS', ZmHex(ZmAbortSequence), ZmHex(log.Sent));
    AssertTrue('cancelled here', log.Result_ = zrCancelledHere);
    AssertEquals('the half file finished, not whole', 1, sink.Incomplete);
  finally
    r.Free;
    log.Free;
    sink.Free;
  end;
  sink := TMemSink.Create;
  log := TZmLog.Create;
  r := TZmReceiver.Create(sink);
  try
    r.OnSend := @log.OnSend;
    r.OnDone := @log.OnDone;
    r.Start(0);
    FeedR(r, ZfileFrame('half.bin', 5000) + ZdataFrame(0, Cycle(1000), ZCRCG) + #24#24#24#24#24#24#24#24#24#24#8#8'$ ');
    AssertTrue('cancelled there', log.Result_ = zrCancelledThere);
    AssertEquals('the half file not whole', 1, sink.Incomplete);
    AssertEquals('what follows the abort', '$ ', log.Leftover);
  finally
    r.Free;
    log.Free;
    sink.Free;
  end;
end;

{ S7. Mutation: "OO" counted into the leftover. }
procedure TTyTerminalZmodemTests.TestOverAndOut;

  procedure Check(const AFeeds: array of RawByteString; ATickMs: Double; const AWant: RawByteString; ADone: Boolean);
  var
    sink: TMemSink;
    log: TZmLog;
    r: TZmReceiver;
    i: Integer;
  begin
    sink := TMemSink.Create;
    log := TZmLog.Create;
    r := TZmReceiver.Create(sink);
    try
      r.OnSend := @log.OnSend;
      r.OnDone := @log.OnDone;
      r.Start(0);
      FeedR(r, ZmEncodeHexHeader(ZmPosHeader(ZFIN, 0)));
      AssertTrue('ZFIN answered', Pos(ZmEncodeHexHeader(ZmPosHeader(ZFIN, 0)), log.Sent) > 0);
      for i := 0 to High(AFeeds) do
        FeedR(r, AFeeds[i]);
      if ATickMs > 0 then
        r.Tick(ATickMs);
      AssertEquals('done', ADone, log.Done);
      if ADone then
      begin
        AssertTrue('ok', log.Result_ = zrOk);
        AssertEquals('leftover', ZmHex(AWant), ZmHex(log.Leftover));
      end;
    finally
      r.Free;
      log.Free;
      sink.Free;
    end;
  end;

begin
  Check(['OOprompt$ '], 0, 'prompt$ ', True);
  Check(['Xprompt'], 0, 'Xprompt', True);
  Check(['O', 'Orest'], 0, 'rest', True);
  Check(['O'], 0, '', False);
  Check(['O'], 1000, '', True);
end;

{ S8 }
procedure TTyTerminalZmodemTests.TestZcommandIsRefused;
var
  sink: TMemSink;
  log: TZmLog;
  r: TZmReceiver;
  e: TZmEscaper;
  cmd, s: RawByteString;
begin
  sink := TMemSink.Create;
  log := TZmLog.Create;
  r := TZmReceiver.Create(sink);
  try
    r.OnSend := @log.OnSend;
    r.OnDone := @log.OnDone;
    r.Start(0);
    log.Sent := '';
    e.Init(False);
    cmd := 'rm -rf ~'#0;
    s := ZmEncodeBinHeader(ZmFlagsHeader(ZCOMMAND, 0, 0, 0, 0), True, e)
      + ZmEncodeSubpacket(@cmd[1], Length(cmd), ZCRCW, True, e);
    FeedR(r, s);
    AssertEquals('the abort', ZmHex(ZmAbortSequence), ZmHex(log.Sent));
    AssertTrue('an error', log.Result_ = zrError);
    AssertEquals('no file', 0, sink.Opens);
  finally
    r.Free;
    log.Free;
    sink.Free;
  end;
end;

{ S9. Mutation: ZEOF's position not checked. }
procedure TTyTerminalZmodemTests.TestAZeofAtTheWrongPlace;
var
  sink: TMemSink;
  log: TZmLog;
  r: TZmReceiver;
  e: TZmEscaper;
begin
  sink := TMemSink.Create;
  log := TZmLog.Create;
  r := TZmReceiver.Create(sink);
  try
    r.OnSend := @log.OnSend;
    r.OnDone := @log.OnDone;
    r.Start(0);
    FeedR(r, ZfileFrame('a.bin', 1500) + ZdataFrame(0, Cycle(1000), ZCRCE));
    log.Sent := '';
    e.Init(False);
    FeedR(r, ZmEncodeBinHeader(ZmPosHeader(ZEOF, 1500), True, e));
    AssertEquals('not finished', 0, sink.Finishes);
    AssertEquals('no ZRINIT', '', ZmHex(log.Sent));
    FeedR(r, ZdataFrame(1000, Cycle(500, 1000), ZCRCE) + ZmEncodeBinHeader(ZmPosHeader(ZEOF, 1500), True, e));
    AssertEquals('now it is', 1, sink.Finishes);
    AssertTrue('whole', sink.Complete[0]);
    AssertTrue('the ZRINIT', Pos(ZmEncodeHexHeader(ZmFlagsHeader(ZRINIT, CANFDX or CANOVIO or CANFC32, 0, 0, 0)), log.Sent) > 0);
    AssertTrue('the bytes', sink.Contents[0] = Cycle(1500));
  finally
    r.Free;
    log.Free;
    sink.Free;
  end;
end;

{ The ZRINIT that answers a ZEOF is lost on the way: the sender repeats its ZEOF, and
  the receiver -- the file closed already -- answers again at once, without a tick of
  its own (its own timeout would repeat the ZRINIT too, 10 s later, and hide this).
  Mutation: a ZEOF with no file open ignored. }
procedure TTyTerminalZmodemTests.TestAZeofRepeatedAfterTheFileIsAnsweredAgain;
var
  sink: TMemSink;
  log: TZmLog;
  r: TZmReceiver;
  e: TZmEscaper;
  rinit, eof: RawByteString;
begin
  rinit := ZmEncodeHexHeader(ZmFlagsHeader(ZRINIT, CANFDX or CANOVIO or CANFC32, 0, 0, 0));
  e.Init(False);
  eof := ZmEncodeBinHeader(ZmPosHeader(ZEOF, 1000), True, e);
  sink := TMemSink.Create;
  log := TZmLog.Create;
  r := TZmReceiver.Create(sink);
  try
    r.OnSend := @log.OnSend;
    r.OnDone := @log.OnDone;
    r.Start(0);
    FeedR(r, ZfileFrame('a.bin', 1000) + ZdataFrame(0, Cycle(1000), ZCRCE));
    log.Sent := '';
    FeedR(r, eof);
    AssertEquals('the file is whole', 1, sink.Finishes);
    AssertTrue('ZRINIT', Pos(rinit, log.Sent) > 0);
    log.Sent := '';                      { lost }
    FeedR(r, eof);
    AssertTrue('the repeated ZEOF answered at once: ' + ZmHex(log.Sent), Pos(rinit, log.Sent) > 0);
    AssertEquals('not a second file', 1, sink.Finishes);
    AssertFalse('still going', log.Done);
  finally
    r.Free;
    log.Free;
    sink.Free;
  end;
end;

{ S10. What sz -e sent to a receiver that had not offered ESCCTL (seen against the
  real sz): a HEX ZSINIT asking for it, then its Attn subpacket (one escaped NUL,
  CRC-16). Mutation: the reader expecting data only after binary headers (sz repeats
  the ZSINIT for ever). }
procedure TTyTerminalZmodemTests.TestAHexZsinitIsAnswered;
const
  SzZsinit: RawByteString = '**'#$18'B02000000400c47'#13#$8A#$11#$18'@'#$18'k'#$DD#$CD#$11;
var
  r: TReaderLog;
  sink: TMemSink;
  log: TZmLog;
  rc: TZmReceiver;
  h: THeaderList;
begin
  r := TReaderLog.Create;
  try
    r.PushEach(SzZsinit);
    AssertEquals('the header', 1, Length(r.Headers));
    AssertEquals('ZSINIT', ZSINIT, r.Headers[0].FrameType);
    AssertEquals('TESCCTL in ZF0', $40, r.Headers[0].P[3]);
    AssertEquals('its subpacket', 1, Length(r.Data));
    AssertEquals('one NUL', ZmHex(#0), ZmHex(r.Data[0]));
    AssertEquals('ZCRCW', ZCRCW, r.Ends[0]);
    AssertTrue('CRC-16 right', r.Oks[0]);
  finally
    r.Free;
  end;
  sink := TMemSink.Create;
  log := TZmLog.Create;
  rc := TZmReceiver.Create(sink);
  try
    rc.OnSend := @log.OnSend;
    rc.Start(0);
    log.Sent := '';
    FeedR(rc, SzZsinit);
    h := THeaderList.Create(log.Sent);
    try
      AssertEquals('answered once', 1, Length(h.Types));
      AssertEquals('with ZACK', ZACK, h.Types[0]);
    finally
      h.Free;
    end;
  finally
    rc.Free;
    log.Free;
    sink.Free;
  end;
end;

{ S11. A window: no more than Window bytes past the last acknowledged place, a ZCRCQ
  every quarter of it, and a ZACK moves it on. Mutation: the window not checked. }
procedure TTyTerminalZmodemTests.TestTheSendersWindow;
var
  src: TMemSource;
  log: TZmLog;
  s: TZmSender;
  got: TSentFiles;
  rpos, ack: RawByteString;
  before: Integer;
  lp: TLoop;
begin
  src := TMemSource.Create;
  log := TZmLog.Create;
  s := TZmSender.Create(src);
  try
    src.Add('w.bin', Cycle(70000));
    s.OnSend := @log.OnSend;
    s.Window := 4096;
    s.Start(InitHeader(0), 0);
    rpos := ZmEncodeHexHeader(ZmPosHeader(ZRPOS, 0));
    s.Input(@rpos[1], Length(rpos), 0);
    got := TSentFiles.Create(log.Sent);
    try
      AssertEquals('stopped at the window', 4096, Length(got.Cur));
    finally
      got.Free;
    end;
    before := Length(log.Sent);
    s.Tick(10);
    AssertEquals('a tick sends nothing more', before, Length(log.Sent));
    ack := ZmEncodeHexHeader(ZmPosHeader(ZACK, 2048));
    s.Input(@ack[1], Length(ack), 20);
    got := TSentFiles.Create(log.Sent);
    try
      AssertEquals('the window moved on by the acknowledged part', 2048 + 4096, Length(got.Cur));
    finally
      got.Free;
    end;
  finally
    s.Free;
    log.Free;
    src.Free;
  end;
  { and a whole transfer with our receiver acknowledging the ZCRCQs }
  lp := TLoop.Create;
  try
    lp.Source.Add('w.bin', Cycle(70000));
    lp.Sender.Window := 4096;
    lp.Run(InitHeader(0));
    AssertTrue('ok', (lp.SLog.Result_ = zrOk) and (lp.RLog.Result_ = zrOk));
    AssertTrue('the same bytes', lp.Sink.Contents[0] = Cycle(70000));
  finally
    lp.Free;
  end;
end;

{ ---- the phase 7 review's fixes --------------------------------------------------------------- }

{ A host whose CanSend answers 0 for good (a pipe that no longer drains): the sender
  waits for room the way it waits for a ZACK, repeats from the last acknowledged place
  every TimeoutMs, and gives up after MaxRetries. Mutation: Pump leaving at "no room"
  without starting that wait (no timeout ever runs; the upload hangs for good). }
procedure TTyTerminalZmodemTests.TestAnUploadWithNoRoomTimesOut;
var
  src: TMemSource;
  log: TZmLog;
  room: TRoom;
  s: TZmSender;
  rpos: RawByteString;
  t: Double;
  i: Integer;
begin
  src := TMemSource.Create;
  log := TZmLog.Create;
  room := TRoom.Create;
  s := TZmSender.Create(src);
  try
    src.Add('stuck.bin', Cycle(5000));
    s.OnSend := @log.OnSend;
    s.OnDone := @log.OnDone;
    room.Value := 0;
    s.CanSend := @room.Allow;
    s.Start(InitHeader(0), 0);
    rpos := ZmEncodeHexHeader(ZmPosHeader(ZRPOS, 0));
    s.Input(@rpos[1], Length(rpos), 0);
    AssertFalse('waiting for room', log.Done);
    t := 0;
    for i := 1 to 15 do
    begin
      t := t + 10001;
      s.Tick(t);
    end;
    AssertTrue('the upload ended', log.Done);
    AssertTrue('timed out: ' + log.Message, log.Result_ = zrTimeout);
    AssertTrue('the abort sent', Pos(ZmAbortSequence, log.Sent) > 0);
  finally
    s.Free;
    room.Free;
    log.Free;
    src.Free;
  end;
end;

{ A file that ends before the size it gave (it shrank while being sent, or a read
  failed): the upload fails with its reason, the abort goes out, and what was sent stays
  small -- with the host's room limited (the example) and unlimited (CanSend nil).
  Mutation: a read of 0 bytes taken as an empty subpacket (the place never moves: empty
  subpackets for ever -- with CanSend nil in one call, which the log's limit stops). }
procedure TTyTerminalZmodemTests.TestAFileThatEndsEarlyFails;

  procedure Run(AWithRoom: Boolean);
  var
    src: TMemSource;
    log: TZmLog;
    room: TRoom;
    s: TZmSender;
    rpos: RawByteString;
    t: Double;
    i: Integer;
    tag: string;
  begin
    if AWithRoom then tag := 'room 4096: ' else tag := 'CanSend nil: ';
    src := TMemSource.Create;
    log := TZmLog.Create;
    room := TRoom.Create;
    s := TZmSender.Create(src);
    try
      src.Add('short.bin', Cycle(1000));
      src.LieSize := 5000;
      log.Limit := 64 * 1024;
      s.OnSend := @log.OnSend;
      s.OnDone := @log.OnDone;
      if AWithRoom then
      begin
        room.Value := 4096;
        s.CanSend := @room.Allow;
      end;
      s.Start(InitHeader(0), 0);
      rpos := ZmEncodeHexHeader(ZmPosHeader(ZRPOS, 0));
      s.Input(@rpos[1], Length(rpos), 0);
      t := 0;
      for i := 1 to 50 do
      begin
        t := t + 100;
        s.Tick(t);
      end;
      AssertTrue(tag + 'ended', log.Done);
      AssertTrue(tag + 'an error: ' + log.Message, log.Result_ = zrError);
      AssertEquals(tag + 'the reason', rsZmReadFailed, log.Message);
      AssertTrue(tag + 'the abort sent', Pos(ZmAbortSequence, log.Sent) > 0);
      AssertTrue(Format('%sa bounded amount sent (%d bytes)', [tag, Length(log.Sent)]), Length(log.Sent) < 8000);
    finally
      s.Free;
      room.Free;
      log.Free;
      src.Free;
    end;
  end;

begin
  Run(True);
  Run(False);
end;

type
  TSkipLog = class
  public
    Names: TStringList;
    Reasons: TStringList;
    constructor Create;
    destructor Destroy; override;
    procedure OnSkip(Sender: TObject; const AName, AReason: string);
  end;

constructor TSkipLog.Create;
begin
  inherited Create;
  Names := TStringList.Create;
  Reasons := TStringList.Create;
end;

destructor TSkipLog.Destroy;
begin
  Names.Free;
  Reasons.Free;
  inherited Destroy;
end;

procedure TSkipLog.OnSkip(Sender: TObject; const AName, AReason: string);
begin
  Names.Add(AName);
  Reasons.Add(AReason);
end;

{ A ZFILE of 4 GiB or more: its positions would wrap at 32 bits, so the receiver skips
  it (ZSKIP) and says why; a smaller one after it is taken. Mutation: the size not
  looked at (the file opened; its positions wrap). }
procedure TTyTerminalZmodemTests.TestA4GiBFileIsSkipped;
var
  sink: TMemSink;
  log: TZmLog;
  skips: TSkipLog;
  r: TZmReceiver;
  h: THeaderList;
begin
  sink := TMemSink.Create;
  log := TZmLog.Create;
  skips := TSkipLog.Create;
  r := TZmReceiver.Create(sink);
  try
    r.OnSend := @log.OnSend;
    r.OnDone := @log.OnDone;
    r.OnFileSkipped := @skips.OnSkip;
    r.Start(0);
    log.Sent := '';
    FeedR(r, ZfileFrame('huge.iso', ZmMaxFileSize));
    AssertEquals('not opened', 0, sink.Opens);
    h := THeaderList.Create(log.Sent);
    try
      AssertEquals('one answer', 1, Length(h.Types));
      AssertEquals('ZSKIP', ZSKIP, h.Types[0]);
    finally
      h.Free;
    end;
    AssertEquals('said so', 1, skips.Names.Count);
    AssertEquals('which', 'huge.iso', skips.Names[0]);
    AssertEquals('why', rsZmTooBig, skips.Reasons[0]);
    FeedR(r, ZfileFrame('small.bin', ZmMaxFileSize - 1));
    AssertEquals('one byte less is taken', 1, sink.Opens);
    AssertFalse('still going', log.Done);
  finally
    r.Free;
    skips.Free;
    log.Free;
    sink.Free;
  end;
end;

{ ---- Task 8: the terminal glue -------------------------------------------------------------- }

procedure TTyTerminalZmodemTests.TestSafeFileNames;

  procedure Check(const AIn, AWant: string);
  begin
    AssertEquals('"' + AIn + '"', AWant, ZmSafeFileName(AIn));
  end;

begin
  Check('../../etc/passwd', 'passwd');
  Check('a\b\c.txt', 'c.txt');
  Check('C:\x\y.bin', 'y.bin');
  Check('a:b*c?"<>|.txt', 'a_b_c_____.txt');
  Check('name. . ', 'name');
  Check('CON', '_CON');
  Check('con.txt', '_con.txt');
  Check('LPT1.log', '_LPT1.log');
  Check('', 'file');
  Check('..', 'file');
  Check('.', 'file');
  Check(#$E6#$8A#$A5#$E5#$91#$8A' 2026.pdf', #$E6#$8A#$A5#$E5#$91#$8A' 2026.pdf');
  Check('a'#1'b'#31'c'#127'd', 'a_b_c_d');
end;

{ Windows' device names, all of them: COM0 / LPT0, the superscript digits (U+00B9,
  U+00B2, U+00B3 -- Windows takes them for 1, 2, 3), CONIN$ / CONOUT$, and a name whose
  part before the first dot ends in spaces ("CON .txt" is CON too). Names that only
  look alike stay. Mutations: the spaces not taken off before the comparison; the
  list without the new names. }
procedure TTyTerminalZmodemTests.TestEveryDeviceNameIsRenamed;

  procedure Check(const AIn, AWant: string);
  begin
    AssertEquals('"' + AIn + '"', AWant, ZmSafeFileName(AIn));
  end;

begin
  Check('COM0', '_COM0');
  Check('lpt0.txt', '_lpt0.txt');
  Check('COM'#$C2#$B9, '_COM'#$C2#$B9);
  Check('COM'#$C2#$B2'.log', '_COM'#$C2#$B2'.log');
  Check('LPT'#$C2#$B3, '_LPT'#$C2#$B3);
  Check('CONIN$', '_CONIN$');
  Check('conout$.txt', '_conout$.txt');
  Check('CON .txt', '_CON .txt');
  Check('nul  .tar.gz', '_nul  .tar.gz');
  Check('AUX.tar.gz', '_AUX.tar.gz');
  Check('COM10', 'COM10');
  Check('CONX', 'CONX');
  Check('CONIN', 'CONIN');
  Check('LPT'#$C2#$B4, 'LPT'#$C2#$B4);
end;

{ a whole UTF-8 string: no sequence cut, none left open }
function WholeUtf8(const S: RawByteString): Boolean;
var
  i, n, k: Integer;
begin
  i := 1;
  while i <= Length(S) do
  begin
    case Ord(S[i]) of
      $00..$7F: n := 0;
      $C2..$DF: n := 1;
      $E0..$EF: n := 2;
      $F0..$F4: n := 3;
    else
      Exit(False);
    end;
    if i + n > Length(S) then
      Exit(False);
    for k := 1 to n do
      if (Ord(S[i + k]) and $C0) <> $80 then
        Exit(False);
    Inc(i, n + 1);
  end;
  Result := True;
end;

{ A remote name longer than 200 bytes (a file system allows 255, and the " (1)" of a
  second copy needs room) is cut to 200, keeping its extension, never inside a UTF-8
  sequence. Mutation: no cut. }
procedure TTyTerminalZmodemTests.TestALongNameIsCut;
var
  s, got: string;
  i: Integer;
begin
  got := ZmSafeFileName(StringOfChar('a', 300) + '.txt');
  AssertEquals('200 bytes', 200, Length(got));
  AssertEquals('the extension kept', StringOfChar('a', 196) + '.txt', got);
  s := '';
  for i := 1 to 150 do
    s := s + #$E4#$B8#$AD;               { U+4E2D, three bytes }
  got := ZmSafeFileName(s + '.bin');
  AssertTrue(Format('at most 200 bytes (%d)', [Length(got)]), Length(got) <= 200);
  AssertTrue('no sequence cut', WholeUtf8(got));
  AssertEquals('the extension kept', '.bin', Copy(got, Length(got) - 3, 4));
  AssertEquals('65 whole characters before it', 65 * 3 + 4, Length(got));
  AssertEquals('no extension: 200', 200, Length(ZmSafeFileName(StringOfChar('x', 250))));
  got := ZmSafeFileName(StringOfChar('a', 300) + '.' + StringOfChar('e', 40));
  AssertEquals('an overlong "extension" is cut like the rest', 200, Length(got));
  AssertEquals('200 bytes stay as they are', StringOfChar('b', 200), ZmSafeFileName(StringOfChar('b', 200)));
  AssertEquals('dots and spaces do not end it', StringOfChar('c', 195) + '.txt',
    ZmSafeFileName(StringOfChar('c', 195) + ' . .' + StringOfChar('d', 100) + '.txt'));
end;

function NewTempDir: string;
begin
  Result := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'tyzm-' + IntToStr(GetTickCount64) + '-'
    + IntToStr(Random(1000000));
  ForceDirectories(Result);
end;

procedure RemoveTempDir(const ADir: string);
var
  sr: TSearchRec;
begin
  if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*', faAnyFile, sr) = 0 then
  begin
    repeat
      if (sr.Name <> '.') and (sr.Name <> '..') then
        DeleteFile(IncludeTrailingPathDelimiter(ADir) + sr.Name);
    until FindNext(sr) <> 0;
    FindClose(sr);
  end;
  RemoveDir(ADir);
end;

function FilesIn(const ADir: string): Integer;
var
  sr: TSearchRec;
begin
  Result := 0;
  if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*', faAnyFile and not faDirectory, sr) = 0 then
  begin
    repeat
      Inc(Result);
    until FindNext(sr) <> 0;
    FindClose(sr);
  end;
end;

procedure Touch(const APath: string);
begin
  with TFileStream.Create(APath, fmCreate) do
    Free;
end;

function FileText(const APath: string): RawByteString;
begin
  Result := ReadBytes(APath);
end;

{ ZmCreateNewFile: the name, else "name (1).ext", "name (2).ext" ..., each created only
  if it is not there -- the check and the creation are one step (CREATE_NEW / O_EXCL),
  so a file that appears in between is never truncated, and a directory of that name
  is passed over. Mutation (review fix): a create that opens what is there (the file
  of that name emptied and taken). }
procedure TTyTerminalZmodemTests.TestUniqueFileNames;
var
  d, path: string;
  h: THandle;

  procedure Take(const AName, AWant: string);
  begin
    h := ZmCreateNewFile(d, AName, path);
    AssertTrue(AName + ': created', h <> THandle(-1));
    FileClose(h);
    AssertEquals(AName, AWant, path);
  end;

begin
  d := NewTempDir;
  try
    with TFileStream.Create(d + PathDelim + 'x.txt', fmCreate) do
    try
      WriteBuffer(PChar('keep')^, 4);
    finally
      Free;
    end;
    Touch(d + PathDelim + 'x (1).txt');
    Take('x.txt', d + PathDelim + 'x (2).txt');
    AssertEquals('what was there is untouched', 'keep', FileText(d + PathDelim + 'x.txt'));
    Touch(d + PathDelim + 'x');
    Take('x', d + PathDelim + 'x (1)');
    ForceDirectories(d + PathDelim + 'sub.d');
    Take('sub.d', d + PathDelim + 'sub (1).d');
    Take('y.txt', d + PathDelim + 'y.txt');
    Take('y.txt', d + PathDelim + 'y (1).txt');
  finally
    RemoveDir(d + PathDelim + 'sub.d');
    RemoveTempDir(d);
  end;
end;

type
  { a core with the ZModem handler on it: its bytes out, its clock, its answers }
  TGlueRig = class
  public
    Core: TTyTerminalCore;
    Zm: TZmodemStreamHandler;
    Sent: RawByteString;
    SentBefore: Integer;
    Now_: Double;
    Dir: string;
    AutoAccept: Boolean;
    Uploads: TStringList;
    Downloads, UploadAsks, Finished: Integer;
    LastResult: TZmResult;
    Allow: Integer;
    constructor Create;
    destructor Destroy; override;
    function Clock: Double;
    function CanSend: Integer;
    procedure OnData(Sender: TObject; const AData: RawByteString);
    procedure OnDownload(Sender: TObject);
    procedure OnUpload(Sender: TObject);
    procedure OnFinished(Sender: TObject; AResult: TZmResult; const AMessage: string);
    procedure OnClaimed(Sender: TObject; const AData: RawByteString);
    function Line(AY: Integer): string;
    function Screen: string;
    procedure WriteIn(const S: RawByteString; APiece: Integer; AStepMs: Double = 0);
  end;

constructor TGlueRig.Create;
begin
  inherited Create;
  Core := TTyTerminalCore.Create(80, 24);
  Core.OnData := @OnData;
  Core.OnClaimedInput := @OnClaimed;
  Zm := TZmodemStreamHandler.Create(Core);
  Zm.Clock := @Clock;
  Zm.CanSend := @CanSend;
  Zm.OnDownloadRequest := @OnDownload;
  Zm.OnUploadRequest := @OnUpload;
  Zm.OnFinished := @OnFinished;
  Uploads := TStringList.Create;
  Dir := NewTempDir;
  Allow := MaxInt;
  Now_ := 1000;
end;

destructor TGlueRig.Destroy;
begin
  Zm.Free;
  Core.Free;
  Uploads.Free;
  RemoveTempDir(Dir);
  inherited Destroy;
end;

function TGlueRig.Clock: Double;
begin
  Result := Now_;
end;

function TGlueRig.CanSend: Integer;
begin
  Result := Allow;
end;

procedure TGlueRig.OnData(Sender: TObject; const AData: RawByteString);
begin
  Sent := Sent + AData;
end;

procedure TGlueRig.OnDownload(Sender: TObject);
begin
  Inc(Downloads);
  if AutoAccept then
    Zm.AcceptDownload(Dir);              { no message loop here: answered at once }
end;

procedure TGlueRig.OnUpload(Sender: TObject);
begin
  Inc(UploadAsks);
  if AutoAccept then
    Zm.StartUpload(Uploads);
end;

procedure TGlueRig.OnFinished(Sender: TObject; AResult: TZmResult; const AMessage: string);
begin
  Inc(Finished);
  LastResult := AResult;
end;

procedure TGlueRig.OnClaimed(Sender: TObject; const AData: RawByteString);
begin
  Zm.UserInput(AData);
end;

function TGlueRig.Line(AY: Integer): string;
begin
  Result := Core.Buffer.TranslateBufferLineToString(Core.Buffer.YBase + AY, True);
end;

function TGlueRig.Screen: string;
var
  y: Integer;
begin
  Result := '';
  for y := 0 to Core.Rows - 1 do
    Result := Result + Line(y) + #10;
end;

procedure TGlueRig.WriteIn(const S: RawByteString; APiece: Integer; AStepMs: Double);
var
  p, n: Integer;
begin
  p := 1;
  while p <= Length(S) do
  begin
    n := Min(APiece, Length(S) - p + 1);
    Now_ := Now_ + AStepMs;
    Core.WriteSync(Copy(S, p, n));
    Inc(p, n);
  end;
end;

{ sz's first bytes: "rz\r" and the ZRQINIT hex header (24 bytes) }
function SzStart: RawByteString;
begin
  Result := Copy(ReadBytes(ZmFixture('one-small.sz.bin')), 1, 24);
end;

{ T1. Mutation: a header taken without its CRC checked. }
procedure TTyTerminalZmodemTests.TestDetection;
var
  r: TGlueRig;
  s, bad, rnd: RawByteString;
  k, i: Integer;
begin
  s := SzStart;
  AssertEquals('the recording starts as expected', ZmHex('rz'#13'**'#$18'B00000000000000'#13#$8A#$11), ZmHex(s));
  r := TGlueRig.Create;
  try
    r.Core.WriteSync(s);
    AssertEquals('asked', 1, r.Downloads);
    AssertEquals('rz shown, the header not', 'rz', r.Line(0));
    AssertTrue('claimed', r.Core.StreamClaimed);
  finally
    r.Free;
  end;
  { the header (18 bytes, then CR LF XON) cut at each of its first 20 bytes: inside it,
    the second piece finds it; after it, the first }
  for k := 1 to 20 do
  begin
    r := TGlueRig.Create;
    try
      r.Core.WriteSync(Copy(s, 1, 3 + k));
      if k < 18 then
        AssertEquals(Format('cut at %d: not yet', [k]), 0, r.Downloads)
      else
        AssertEquals(Format('cut at %d: whole in the first piece', [k]), 1, r.Downloads);
      r.Core.WriteSync(Copy(s, 4 + k, MaxInt));
      AssertEquals(Format('cut at %d: found', [k]), 1, r.Downloads);
      AssertTrue(Format('cut at %d: claimed', [k]), r.Core.StreamClaimed);
    finally
      r.Free;
    end;
  end;
  { a CRC that does not fit }
  r := TGlueRig.Create;
  try
    bad := 'rz'#13'**'#$18'B00000000000001'#13#$8A#$11;
    r.Core.WriteSync(bad);
    AssertEquals('a bad CRC is not a header', 0, r.Downloads);
    AssertFalse('not claimed', r.Core.StreamClaimed);
    { ten megabytes of seeded random bytes, with that bad header in them now and then }
    RandSeed := 1234;
    rnd := '';
    SetLength(rnd, 1024 * 1024);
    for i := 1 to 10 do
    begin
      for k := 1 to Length(rnd) do
        rnd[k] := AnsiChar(Random(256));
      Move(bad[1], rnd[1000 * i], Length(bad));
      r.Core.WriteSync(rnd);
    end;
    AssertEquals('no false detection', 0, r.Downloads + r.UploadAsks);
  finally
    r.Free;
  end;
  { rz's ZRINIT: an upload }
  r := TGlueRig.Create;
  try
    r.Core.WriteSync('rz waiting to receive.' + Copy(ReadBytes(ZmFixture('one-small.rz.bin')), 1, 21));
    AssertEquals('an upload asked for', 1, r.UploadAsks);
    AssertEquals('no download', 0, r.Downloads);
  finally
    r.Free;
  end;
end;

{ T2. Mutation: the receiver started as soon as the stream is claimed. }
procedure TTyTerminalZmodemTests.TestNothingIsSentBeforeTheAnswer;
var
  r: TGlueRig;
  h: THeaderList;
begin
  r := TGlueRig.Create;
  try
    r.Core.WriteSync(SzStart);
    r.Core.WriteSync(SzStart);             { sz repeats itself while we ask }
    AssertEquals('asked once', 1, r.Downloads);
    AssertEquals('nothing sent before the answer', '', ZmHex(r.Sent));
    r.Zm.AcceptDownload(r.Dir);
    h := THeaderList.Create(r.Sent);
    try
      AssertTrue('something sent', Length(h.Types) > 0);
      AssertEquals('ZRINIT first', ZRINIT, h.Types[0]);
    finally
      h.Free;
    end;
  finally
    r.Free;
  end;
end;

function FindLine(r: TGlueRig; const AText: string): Integer;
var
  y: Integer;
begin
  for y := 0 to r.Core.Rows - 1 do
    if Pos(AText, r.Line(y)) > 0 then
      Exit(y);
  Result := -1;
end;

{ T3. Mutation: no Release at the end. }
procedure TTyTerminalZmodemTests.TestAWholeDownload;
var
  r: TGlueRig;
  y: Integer;
  want: RawByteString;
begin
  want := ReadBytes(ZmFixture('one-small.1.src'));
  r := TGlueRig.Create;
  try
    r.AutoAccept := True;
    r.WriteIn(ReadBytes(ZmFixture('one-small.sz.bin')), 100);
    AssertEquals('finished once', 1, r.Finished);
    AssertTrue('ok', r.LastResult = zrOk);
    AssertFalse('the stream is back', r.Core.StreamClaimed);
    AssertTrue('the file is there', FileExists(r.Dir + PathDelim + 'one-small.bin'));
    AssertTrue('its bytes', ReadBytes(r.Dir + PathDelim + 'one-small.bin') = want);
    AssertEquals('the saved list', 1, r.Zm.LastSaved.Count);
    y := FindLine(r, 'Received 1 file(s), 1.5 KB');
    AssertTrue('the summary line: ' + r.Screen, y >= 0);
    r.Core.WriteSync('$ ');
    AssertEquals('the prompt below it', '$', Trim(r.Line(y + 1)));
  finally
    r.Free;
  end;
end;

{ T4. Mutation: the 200 ms rule dropped. }
procedure TTyTerminalZmodemTests.TestProgressIsThrottled;
var
  r: TGlueRig;
  sz: RawByteString;
begin
  sz := ReadBytes(ZmFixture('window.sz.bin'));
  r := TGlueRig.Create;
  try
    r.AutoAccept := True;
    r.WriteIn(sz, (Length(sz) + 39) div 40, 50);
    AssertTrue('ok', r.LastResult = zrOk);
    AssertTrue('some progress', r.Zm.ProgressLines > 0);
    AssertTrue(Format('at most 11 lines in 2 s, got %d', [r.Zm.ProgressLines]), r.Zm.ProgressLines <= 11);
  finally
    r.Free;
  end;
end;

{ T5. Mutation: the Ctrl+X count not reset by another byte. }
procedure TTyTerminalZmodemTests.TestFiveCtrlXCancel;
var
  r: TGlueRig;
  sz: RawByteString;
begin
  sz := ReadBytes(ZmFixture('big-block.sz.bin'));
  r := TGlueRig.Create;
  try
    r.AutoAccept := True;
    r.WriteIn(Copy(sz, 1, 3000), 500);
    AssertTrue('receiving', r.Zm.State = zsReceiving);
    AssertEquals('a half file', 1, FilesIn(r.Dir));
    r.Core.Input(#24#24'a'#24#24#24, True);
    AssertTrue('broken run: still receiving', r.Zm.State = zsReceiving);
    r.Core.Input('x', True);             { the three CANs above end here }
    r.Core.Input(#24#24#24#24, True);
    AssertTrue('four: still receiving', r.Zm.State = zsReceiving);
    r.Sent := '';
    r.Core.Input(#24, True);
    AssertTrue('five in a row: idle', r.Zm.State = zsIdle);
    AssertEquals('the abort sent', ZmHex(ZmAbortSequence), ZmHex(r.Sent));
    AssertTrue('cancelled here', r.LastResult = zrCancelledHere);
    AssertEquals('the half file deleted', 0, FilesIn(r.Dir));
    AssertFalse('the stream is back', r.Core.StreamClaimed);
  finally
    r.Free;
  end;
end;

{ T6. Mutation: WindowsPty not looked at. }
procedure TTyTerminalZmodemTests.TestRefusedBehindConPty;
var
  r: TGlueRig;
  pty: TTyTerminalWindowsPty;
begin
  pty.Backend := twpConPty;
  pty.BuildNumber := 19044;
  r := TGlueRig.Create;
  try
    r.Core.WindowsPty := pty;
    r.Core.WriteSync(SzStart + 'after');
    AssertEquals('not asked', 0, r.Downloads);
    AssertEquals('the abort', ZmHex(ZmAbortSequence), ZmHex(r.Sent));
    AssertTrue('the line: ' + r.Screen, FindLine(r, 'ConPTY damages binary data') >= 0);
    AssertTrue('what followed the header shown', FindLine(r, 'after') >= 0);
    AssertTrue('an error', r.LastResult = zrError);
    AssertFalse('the stream is back', r.Core.StreamClaimed);
  finally
    r.Free;
  end;
  r := TGlueRig.Create;
  try
    r.Core.WindowsPty := pty;
    r.Zm.RefuseBehindConPty := False;
    r.Core.WriteSync(SzStart);
    AssertEquals('asked as usual', 1, r.Downloads);
  finally
    r.Free;
  end;
end;

{ T7. Mutation: ClaimEnded not cancelling the machine. }
procedure TTyTerminalZmodemTests.TestResetMidDownload;
var
  r: TGlueRig;
begin
  r := TGlueRig.Create;
  try
    r.AutoAccept := True;
    r.WriteIn(Copy(ReadBytes(ZmFixture('big-block.sz.bin')), 1, 3000), 500);
    AssertEquals('a half file', 1, FilesIn(r.Dir));
    r.Sent := '';
    r.Core.Reset;
    AssertEquals('the abort sent', ZmHex(ZmAbortSequence), ZmHex(r.Sent));
    AssertEquals('the half file deleted', 0, FilesIn(r.Dir));
    AssertTrue('idle', r.Zm.State = zsIdle);
    AssertFalse('not claimed', r.Core.StreamClaimed);
  finally
    r.Free;
  end;
end;

{ T8. Mutation: the sender not asking CanSend. }
procedure TTyTerminalZmodemTests.TestUploadIsThrottled;
var
  r: TGlueRig;
  f: string;
  data: RawByteString;
  before, grown: Integer;
begin
  r := TGlueRig.Create;
  try
    f := r.Dir + PathDelim + 'up.bin';
    data := Cycle(70000);
    with TFileStream.Create(f, fmCreate) do
    try
      WriteBuffer(data[1], Length(data));
    finally
      Free;
    end;
    r.Uploads.Add(f);
    r.AutoAccept := True;
    r.Allow := 0;
    r.Core.WriteSync(Copy(ReadBytes(ZmFixture('one-small.rz.bin')), 1, 21));
    AssertTrue('sending', r.Zm.State = zsSending);
    { rz's answer to the ZFILE: from the start }
    r.Core.WriteSync(ZmEncodeHexHeader(ZmPosHeader(ZRPOS, 0)));
    before := Length(r.Sent);
    r.Now_ := r.Now_ + 100;
    r.Zm.Tick(r.Now_);
    AssertEquals('CanSend 0: nothing more', before, Length(r.Sent));
    r.Allow := 4096;
    r.Now_ := r.Now_ + 100;
    r.Zm.Tick(r.Now_);
    grown := Length(r.Sent) - before;
    AssertTrue('CanSend 4096: some data', grown > 0);
    AssertTrue(Format('CanSend 4096: at most one packet over, got %d', [grown]), grown <= 4096 + 2 * ZmSendSubpacket + 16);
  finally
    r.Free;
  end;
end;

{ a sparse file of ASize bytes (nothing written: no disk space taken); False when the
  file system cannot make one }
function MakeSparseFile(const APath: string; ASize: Int64): Boolean;
var
  fs: TFileStream;
  {$IFDEF MSWINDOWS}
  ret: LongWord;
  {$ENDIF}
begin
  fs := TFileStream.Create(APath, fmCreate);
  try
    {$IFDEF MSWINDOWS}
    ret := 0;
    if not TyDeviceIoControl(fs.Handle, $000900C4 { FSCTL_SET_SPARSE }, nil, 0, nil, 0, ret, nil) then
      Exit(False);
    {$ENDIF}
    fs.Size := ASize;
    Result := fs.Size = ASize;
  finally
    fs.Free;
  end;
end;

{ In the terminal: a 4 GiB download is skipped with a line saying why; a 4 GiB upload
  is refused before anything is sent -- the abort to rz, the reason on the screen, the
  stream back. Mutations: the receiver's skip not shown; the upload's size not looked
  at (a ZFILE goes out whose size the positions cannot reach). }
procedure TTyTerminalZmodemTests.TestA4GiBFileInTheTerminal;
var
  r: TGlueRig;
  f: string;
  h: THeaderList;
  k: Integer;
begin
  r := TGlueRig.Create;
  try
    r.AutoAccept := True;
    r.Core.WriteSync(SzStart);
    AssertTrue('receiving', r.Zm.State = zsReceiving);
    r.Core.WriteSync(ZfileFrame('huge.iso', ZmMaxFileSize));
    AssertTrue('the skip on the screen: ' + r.Screen, FindLine(r, 'huge.iso') >= 0);
    AssertTrue('and why: ' + r.Screen, FindLine(r, rsZmTooBig) >= 0);
    AssertEquals('no file', 0, FilesIn(r.Dir));
  finally
    r.Free;
  end;
  r := TGlueRig.Create;
  try
    f := r.Dir + PathDelim + 'huge.img';
    if not MakeSparseFile(f, ZmMaxFileSize) then
      Ignore('this file system makes no sparse file of 4 GiB');
    r.Uploads.Add(f);
    r.AutoAccept := True;
    r.Core.WriteSync(Copy(ReadBytes(ZmFixture('one-small.rz.bin')), 1, 21) + '$ ');
    AssertTrue('idle', r.Zm.State = zsIdle);
    AssertFalse('the stream is back', r.Core.StreamClaimed);
    h := THeaderList.Create(r.Sent);
    try
      for k := 0 to High(h.Types) do
        AssertTrue('no ZFILE', h.Types[k] <> ZFILE);
    finally
      h.Free;
    end;
    AssertTrue('the abort sent', Pos(ZmAbortSequence, r.Sent) > 0);
    AssertTrue('an error', r.LastResult = zrError);
    AssertTrue('why, on the screen: ' + r.Screen, FindLine(r, rsZmTooBig) >= 0);
  finally
    r.Free;
  end;
end;

{ What the program wrote while we asked -- sz's repeated header, its abort once it gave
  up, then the shell's prompt -- is not dropped when the transfer is declined: the
  prompt shows under the "declined" line; the headers do not show and are not found
  again. The same when the host takes the handler off while it asks (ClaimEnded, where
  Release does nothing). Mutations: Decline handing back nothing; handing back all it
  kept (the header found again: a second request); ClaimEnded dropping it. }
procedure TTyTerminalZmodemTests.TestDecliningShowsWhatFollowed;
var
  r: TGlueRig;
  y: Integer;
begin
  r := TGlueRig.Create;
  try
    r.Core.WriteSync(SzStart);
    AssertEquals('asked', 1, r.Downloads);
    r.Core.WriteSync(Copy(SzStart, 4, MaxInt) + ZmAbortSequence + '$ ');
    r.Zm.Decline;
    r.Core.WriteSync('');                { the bytes handed back wait for the next slice }
    y := FindLine(r, rsZmDeclined);
    AssertTrue('the declined line: ' + r.Screen, y >= 0);
    AssertEquals('the prompt under it: ' + r.Screen, '$', Trim(r.Line(y + 1)));
    AssertEquals('not asked again', 1, r.Downloads);
    AssertFalse('the stream is back', r.Core.StreamClaimed);
    AssertEquals('no header on the screen', 0, Pos('B0000', r.Screen));
  finally
    r.Free;
  end;
  r := TGlueRig.Create;
  try
    r.Core.WriteSync(SzStart);
    r.Core.WriteSync('$ ');
    r.Core.RemoveStreamHandler(r.Zm);
    AssertFalse('the stream is back', r.Core.StreamClaimed);
    AssertTrue('the prompt shown: ' + r.Screen, FindLine(r, '$') >= 0);
    AssertEquals('no header on the screen', 0, Pos('B0000', r.Screen));
  finally
    r.Free;
  end;
end;

initialization
  RegisterTest(TTyTerminalZmodemTests);
end.
