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
  end;

{ bytes as two-digit hex separated by spaces (failure messages) }
function ZmHex(const S: RawByteString): string;

implementation

uses
  StrUtils;

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

initialization
  RegisterTest(TTyTerminalZmodemTests);
end.
