unit uzmodem;

{ ZMODEM for the terminal example (phase 7, design spec 19.7): the constants, the two
  CRCs, ZDLE escaping, header and data subpacket encoding, the file information block,
  and a frame reader fed a byte at a time. The session state machines are in
  uzmodemsession, the terminal glue in uzmodemterm.

  WRITTEN FOR THIS LIBRARY. The protocol follows Chuck Forsberg, "The ZMODEM Inter
  Application File Transfer Protocol", Omen Technology, Rev Oct-14-88 -- a public
  domain protocol (the document says so). It contains NO code from lrzsz (its licence is not ours): lrzsz
  is only the program the tests talk to, and what it sends on the wire (recorded, spec
  19.2 item 11) is what the tests compare with.

  Byte order, because it is easy to get wrong:
    - a header's four bytes P[0..3] are ZP0..ZP3: a file position little-endian, or the
      flags with ZF0 in P[3] (ZF3 in P[0]);
    - a hex header sends its CRC-16 high byte first, in LOWER-case hex digits (lrzsz
      sends lower case; the reader takes both), then CR and LF with the high bit set,
      then XON -- but not after ZACK and ZFIN;
    - a binary CRC-32 is sent inverted, low byte first; a CRC-16 high byte first;
    - a data subpacket's CRC covers its data and the frame-end byte.

  Only SysUtils and Classes: the tests and the WSL console tool use it without the LCL. }

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, Classes;

const
  ZPAD = $2A; ZDLE = $18; ZDLEE = $58; ZBIN = $41; ZHEX = $42; ZBIN32 = $43;
  ZRQINIT = 0; ZRINIT = 1; ZSINIT = 2; ZACK = 3; ZFILE = 4; ZSKIP = 5; ZNAK = 6;
  ZABORT = 7; ZFIN = 8; ZRPOS = 9; ZDATA = 10; ZEOF = 11; ZFERR = 12; ZCRC = 13;
  ZCHALLENGE = 14; ZCOMPL = 15; ZCAN = 16; ZFREECNT = 17; ZCOMMAND = 18; ZSTDERR = 19;
  ZCRCE = $68; ZCRCG = $69; ZCRCQ = $6A; ZCRCW = $6B; ZRUB0 = $6C; ZRUB1 = $6D;
  { ZRINIT ZF0 }
  CANFDX = $01; CANOVIO = $02; CANBRK = $04; CANCRY = $08; CANLZW = $10; CANFC32 = $20;
  ESCCTL = $40; ESC8 = $80;
  { ZFILE ZF0: binary }
  ZCBIN = 1;
  ZmMaxRecvSubpacket = 8192;
  ZmSendSubpacket = 1024;
  { a header's position is 32 bits: a file this long or longer cannot be carried }
  ZmMaxFileSize = Int64($100000000);
  { what lrzsz sends to abort, as seen on the wire (spec 19.2 item 11) }
  ZmAbortSequence = #24#24#24#24#24#24#24#24#24#24#8#8#8#8#8#8#8#8#8#8;

type
  TZmHeaderKind = (zhkHex, zhkBin16, zhkBin32);
  { P[0..3] = ZP0..ZP3 = ZF3..ZF0: a position little-endian, flags ZF0 in P[3] }
  TZmHeader = record
    FrameType: Byte;
    P: array[0..3] of Byte;
  end;

  TZmEscaper = record
    EscCtl: Boolean;          { the peer asked for ESCCTL: every control character }
    LastSent: Byte;           { CR after '@' is escaped (telnet), so this carries }
    procedure Init(AEscCtl: Boolean);
    function Escape(AData: PByte; ACount: Integer): RawByteString;
  end;

function ZmCrc16(ACrc: Word; AData: PByte; ACount: Integer): Word;          { XMODEM, $1021, MSB first }
function ZmCrc32(ACrc: Cardinal; AData: PByte; ACount: Integer): Cardinal;  { reflected $EDB88320; caller starts at $FFFFFFFF and inverts }
function ZmPosHeader(AType: Byte; APos: Cardinal): TZmHeader;
function ZmFlagsHeader(AType, AF0, AF1, AF2, AF3: Byte): TZmHeader;
function ZmHeaderPos(const AHeader: TZmHeader): Cardinal;
function ZmEncodeHexHeader(const AHeader: TZmHeader): RawByteString;
function ZmEncodeBinHeader(const AHeader: TZmHeader; ACrc32: Boolean; var AEsc: TZmEscaper): RawByteString;
function ZmEncodeSubpacket(AData: PByte; ACount: Integer; AEnd: Byte; ACrc32: Boolean;
  var AEsc: TZmEscaper): RawByteString;
{ 'name'#0'size mtime mode serial filesleft bytesleft'#0 -- size decimal, mtime / mode octal }
function ZmBuildFileInfo(const AName: string; ASize, AMTime: Int64; AFilesLeft: Integer; ABytesLeft: Int64): RawByteString;
{ False when there is no name or the size is not a number; a missing mtime is -1, a
  missing mode 0 }
function ZmParseFileInfo(const AData: RawByteString; out AName: string; out ASize, AMTime: Int64;
  out AMode: Cardinal): Boolean;
function ZmFrameName(AType: Integer): string;

type
  TZmReaderHeaderEvent = procedure(const AHeader: TZmHeader; AKind: TZmHeaderKind) of object;
  { AEnd 0 with ACrcOk False: a subpacket too long or badly escaped }
  TZmReaderDataEvent = procedure(const AData: RawByteString; AEnd: Byte; ACrcOk: Boolean) of object;

  TZmReaderState = (zrsSeek, zrsPad, zrsPadDle, zrsHex, zrsHexTail, zrsBin, zrsData, zrsDataCrc);

  { byte-at-a-time frame reader: headers anywhere in garbage; after a ZDATA / ZFILE /
    ZSINIT / ZCOMMAND header, data subpackets in that header's CRC (a hex header's
    are CRC-16, after its CR LF: sz -e sends its ZSINIT so) until one ends ZCRCE or
    ZCRCW. Unescaped XON / XOFF (with or without the high bit) are dropped; five ZDLE
    (CAN) in a row is the peer aborting. }
  TZmReader = class
  private
    FState: TZmReaderState;
    FKind: TZmHeaderKind;
    FBuf: array[0..8] of Byte;             { a header's bytes, or a CRC's }
    FCount, FNeed: Integer;
    FEscaped: Boolean;                     { the last byte was a ZDLE (binary and data) }
    FHexHigh: Integer;                     { -1 or the high nibble waiting }
    FData: RawByteString;
    FDataLen: Integer;
    FDataCrc32: Boolean;
    FEnd: Byte;
    FCanRun: Integer;
    FGarbage: Integer;
    FStopped: Boolean;
    FTailData: Boolean;                    { a hex header whose data follows its CR LF }
    FMaxSubpacket: Integer;
    FOnHeader: TZmReaderHeaderEvent;
    FOnData: TZmReaderDataEvent;
    FOnCancel: TNotifyEvent;
    procedure Garbage;
    procedure HeaderDone;
    procedure DataByte(B: Byte);
    procedure DataDone;
    procedure DataFailed;
    procedure Feed(B: Byte);
    procedure Step(B: Byte);
    procedure EndHexTail;
    function GetInData: Boolean;
  public
    constructor Create;
    { consumes AData[0..ACount-1] until Stop is called from an event; answers how many
      bytes were consumed }
    function Push(AData: PByte; ACount: Integer): Integer;
    procedure Stop;                 { from an event: Push returns right after this byte }
    procedure ExpectData(ACrc32: Boolean);   { e.g. after a ZDATA the receiver accepts }
    procedure DropData;             { back to looking for headers (after sending ZRPOS) }
    property OnHeader: TZmReaderHeaderEvent read FOnHeader write FOnHeader;
    property OnData: TZmReaderDataEvent read FOnData write FOnData;
    property OnCancel: TNotifyEvent read FOnCancel write FOnCancel;
    { bytes skipped looking for a header since the last one (in OnHeader: the bytes
      before this one) }
    property GarbageCount: Integer read FGarbage;
    { a longer data subpacket is an error; default ZmMaxRecvSubpacket }
    property MaxSubpacket: Integer read FMaxSubpacket write FMaxSubpacket;
    { reading data subpackets (after a binary ZDATA / ZFILE / ZSINIT / ZCOMMAND) }
    property InData: Boolean read GetInData;
  end;

implementation

const
  HexDigits: array[0..15] of AnsiChar = '0123456789abcdef';

var
  { a byte at a time (built in the initialization, bit by bit as below) }
  Crc16Table: array[0..255] of Word;
  Crc32Table: array[0..255] of Cardinal;

procedure BuildCrcTables;
var
  i, b: Integer;
  c16: Word;
  c32: Cardinal;
begin
  for i := 0 to 255 do
  begin
    { XMODEM: $1021, most significant bit first }
    c16 := Word(i shl 8);
    for b := 1 to 8 do
      if (c16 and $8000) <> 0 then
        c16 := Word((c16 shl 1) xor $1021)
      else
        c16 := Word(c16 shl 1);
    Crc16Table[i] := c16;
    { IEEE, reflected: $EDB88320, least significant bit first }
    c32 := i;
    for b := 1 to 8 do
      if (c32 and 1) <> 0 then
        c32 := (c32 shr 1) xor $EDB88320
      else
        c32 := c32 shr 1;
    Crc32Table[i] := c32;
  end;
end;

function ZmCrc16(ACrc: Word; AData: PByte; ACount: Integer): Word;
var
  i: Integer;
begin
  Result := ACrc;
  for i := 0 to ACount - 1 do
    Result := Word(Result shl 8) xor Crc16Table[(Result shr 8) xor AData[i]];
end;

function ZmCrc32(ACrc: Cardinal; AData: PByte; ACount: Integer): Cardinal;
var
  i: Integer;
begin
  Result := ACrc;
  for i := 0 to ACount - 1 do
    Result := (Result shr 8) xor Crc32Table[(Result xor AData[i]) and $FF];
end;

function ZmPosHeader(AType: Byte; APos: Cardinal): TZmHeader;
begin
  Result.FrameType := AType;
  Result.P[0] := APos and $FF;
  Result.P[1] := (APos shr 8) and $FF;
  Result.P[2] := (APos shr 16) and $FF;
  Result.P[3] := (APos shr 24) and $FF;
end;

function ZmFlagsHeader(AType, AF0, AF1, AF2, AF3: Byte): TZmHeader;
begin
  Result.FrameType := AType;
  Result.P[3] := AF0;
  Result.P[2] := AF1;
  Result.P[1] := AF2;
  Result.P[0] := AF3;
end;

function ZmHeaderPos(const AHeader: TZmHeader): Cardinal;
begin
  Result := Cardinal(AHeader.P[0]) or (Cardinal(AHeader.P[1]) shl 8) or (Cardinal(AHeader.P[2]) shl 16)
    or (Cardinal(AHeader.P[3]) shl 24);
end;

function HeaderBytes(const AHeader: TZmHeader): RawByteString;
begin
  Result := AnsiChar(AHeader.FrameType) + AnsiChar(AHeader.P[0]) + AnsiChar(AHeader.P[1])
    + AnsiChar(AHeader.P[2]) + AnsiChar(AHeader.P[3]);
end;

function Hex2(B: Byte): RawByteString;
begin
  Result := HexDigits[B shr 4] + HexDigits[B and 15];
end;

function ZmEncodeHexHeader(const AHeader: TZmHeader): RawByteString;
var
  b: RawByteString;
  crc: Word;
  i: Integer;
begin
  b := HeaderBytes(AHeader);
  crc := ZmCrc16(0, @b[1], 5);
  Result := '**'#$18'B';
  for i := 1 to 5 do
    Result := Result + Hex2(Ord(b[i]));
  Result := Result + Hex2(crc shr 8) + Hex2(crc and $FF) + #13#$8A;
  { the spec: no XON after ZACK and ZFIN (the other side may stop reading there) }
  if (AHeader.FrameType <> ZACK) and (AHeader.FrameType <> ZFIN) then
    Result := Result + #$11;
end;

function ZmEncodeBinHeader(const AHeader: TZmHeader; ACrc32: Boolean; var AEsc: TZmEscaper): RawByteString;
var
  b: RawByteString;
  crc16: Word;
  crc32: Cardinal;
begin
  b := HeaderBytes(AHeader);
  if ACrc32 then
  begin
    crc32 := not ZmCrc32($FFFFFFFF, @b[1], 5);
    b := b + AnsiChar(crc32 and $FF) + AnsiChar((crc32 shr 8) and $FF) + AnsiChar((crc32 shr 16) and $FF)
      + AnsiChar(crc32 shr 24);
    Result := #$2A#$18'C';
  end
  else
  begin
    crc16 := ZmCrc16(0, @b[1], 5);
    b := b + AnsiChar(crc16 shr 8) + AnsiChar(crc16 and $FF);
    Result := #$2A#$18'A';
  end;
  Result := Result + AEsc.Escape(@b[1], Length(b));
end;

function ZmEncodeSubpacket(AData: PByte; ACount: Integer; AEnd: Byte; ACrc32: Boolean;
  var AEsc: TZmEscaper): RawByteString;
var
  crc16: Word;
  crc32: Cardinal;
  e: Byte;
  tail: RawByteString;
begin
  e := AEnd;
  if ACount > 0 then
    Result := AEsc.Escape(AData, ACount)
  else
    Result := '';
  Result := Result + #$18 + AnsiChar(AEnd);
  AEsc.LastSent := AEnd;
  if ACrc32 then
  begin
    crc32 := ZmCrc32($FFFFFFFF, AData, ACount);
    crc32 := not ZmCrc32(crc32, @e, 1);
    tail := AnsiChar(crc32 and $FF) + AnsiChar((crc32 shr 8) and $FF) + AnsiChar((crc32 shr 16) and $FF)
      + AnsiChar(crc32 shr 24);
  end
  else
  begin
    crc16 := ZmCrc16(0, AData, ACount);
    crc16 := ZmCrc16(crc16, @e, 1);
    tail := AnsiChar(crc16 shr 8) + AnsiChar(crc16 and $FF);
  end;
  Result := Result + AEsc.Escape(@tail[1], Length(tail));
end;

{ ---- TZmEscaper ------------------------------------------------------------------------ }

procedure TZmEscaper.Init(AEscCtl: Boolean);
begin
  EscCtl := AEscCtl;
  LastSent := 0;
end;

function TZmEscaper.Escape(AData: PByte; ACount: Integer): RawByteString;
var
  i, n: Integer;
  c: Byte;
  esc: Boolean;
begin
  Result := '';
  SetLength(Result, ACount * 2);
  n := 0;
  for i := 0 to ACount - 1 do
  begin
    c := AData[i];
    case c of
      $10, $11, $13, $18, $90, $91, $93: esc := True;
      $0D, $8D: esc := EscCtl or ((LastSent and $7F) = $40);
    else
      esc := EscCtl and ((c and $60) = 0);
    end;
    if esc then
    begin
      Inc(n);
      Result[n] := AnsiChar(ZDLE);
      c := c xor $40;
    end;
    Inc(n);
    Result[n] := AnsiChar(c);
    LastSent := c;
  end;
  SetLength(Result, n);
end;

{ ---- the file information block ------------------------------------------------------------ }

function Octal(AValue: Int64): string;
begin
  if AValue <= 0 then
    Exit('0');
  Result := '';
  while AValue > 0 do
  begin
    Result := Chr(Ord('0') + (AValue and 7)) + Result;
    AValue := AValue shr 3;
  end;
end;

function ZmBuildFileInfo(const AName: string; ASize, AMTime: Int64; AFilesLeft: Integer; ABytesLeft: Int64): RawByteString;
begin
  Result := AName + #0 + IntToStr(ASize) + ' ' + Octal(AMTime) + ' 100644 0 ' + IntToStr(AFilesLeft)
    + ' ' + IntToStr(ABytesLeft) + #0;
end;

function ParseOctal(const S: string; out AValue: Int64): Boolean;
var
  i: Integer;
begin
  AValue := 0;
  Result := S <> '';
  for i := 1 to Length(S) do
    if S[i] in ['0'..'7'] then
      AValue := AValue * 8 + (Ord(S[i]) - Ord('0'))
    else
      Exit(False);
end;

function ParseDecimal(const S: string; out AValue: Int64): Boolean;
var
  i: Integer;
begin
  AValue := 0;
  Result := S <> '';
  for i := 1 to Length(S) do
    if S[i] in ['0'..'9'] then
      AValue := AValue * 10 + (Ord(S[i]) - Ord('0'))
    else
      Exit(False);
end;

function ZmParseFileInfo(const AData: RawByteString; out AName: string; out ASize, AMTime: Int64;
  out AMode: Cardinal): Boolean;
var
  p, q: Integer;
  rest: string;
  fields: TStringList;
  v: Int64;
begin
  AName := '';
  ASize := -1;
  AMTime := -1;
  AMode := 0;
  Result := False;
  p := Pos(#0, AData);
  if p <= 1 then
    Exit;
  AName := Copy(AData, 1, p - 1);
  rest := Copy(AData, p + 1, MaxInt);
  q := Pos(#0, rest);
  if q > 0 then
    rest := Copy(rest, 1, q - 1);
  fields := TStringList.Create;
  try
    fields.Delimiter := ' ';
    fields.StrictDelimiter := True;
    fields.DelimitedText := Trim(rest);
    if (fields.Count < 1) or not ParseDecimal(fields[0], ASize) then
      Exit;
    if (fields.Count >= 2) and ParseOctal(fields[1], v) then
      AMTime := v;
    if (fields.Count >= 3) and ParseOctal(fields[2], v) then
      AMode := Cardinal(v);
    Result := True;
  finally
    fields.Free;
  end;
end;

function ZmFrameName(AType: Integer): string;
const
  Names: array[0..19] of string = ('ZRQINIT', 'ZRINIT', 'ZSINIT', 'ZACK', 'ZFILE', 'ZSKIP', 'ZNAK',
    'ZABORT', 'ZFIN', 'ZRPOS', 'ZDATA', 'ZEOF', 'ZFERR', 'ZCRC', 'ZCHALLENGE', 'ZCOMPL', 'ZCAN',
    'ZFREECNT', 'ZCOMMAND', 'ZSTDERR');
begin
  if (AType >= 0) and (AType <= High(Names)) then
    Result := Names[AType]
  else
    Result := 'frame ' + IntToStr(AType);
end;

{ ---- TZmReader ------------------------------------------------------------------------ }

constructor TZmReader.Create;
begin
  inherited Create;
  FMaxSubpacket := ZmMaxRecvSubpacket;
  FHexHigh := -1;
end;

procedure TZmReader.Stop;
begin
  FStopped := True;
end;

procedure TZmReader.ExpectData(ACrc32: Boolean);
begin
  FTailData := False;
  FState := zrsData;
  FDataCrc32 := ACrc32;
  FDataLen := 0;
  FEscaped := False;
end;

procedure TZmReader.DropData;
begin
  FTailData := False;
  FState := zrsSeek;
  FEscaped := False;
  FDataLen := 0;
end;

function TZmReader.GetInData: Boolean;
begin
  Result := FState in [zrsData, zrsDataCrc];
end;

procedure TZmReader.Garbage;
begin
  Inc(FGarbage);
  FState := zrsSeek;
end;

procedure TZmReader.HeaderDone;
var
  h: TZmHeader;
  ok: Boolean;
  crc32: Cardinal;
  kind: TZmHeaderKind;
begin
  case FKind of
    zhkBin32:
      begin
        crc32 := not ZmCrc32($FFFFFFFF, @FBuf[0], 5);
        ok := (FBuf[5] = crc32 and $FF) and (FBuf[6] = (crc32 shr 8) and $FF)
          and (FBuf[7] = (crc32 shr 16) and $FF) and (FBuf[8] = crc32 shr 24);
      end;
  else
    ok := ZmCrc16(0, @FBuf[0], 5) = (Word(FBuf[5]) shl 8) or FBuf[6];
  end;
  if not ok then
  begin
    { a header with a bad CRC is garbage: counted, then look again }
    Inc(FGarbage);
    FState := zrsSeek;
    Exit;
  end;
  h.FrameType := FBuf[0];
  h.P[0] := FBuf[1];
  h.P[1] := FBuf[2];
  h.P[2] := FBuf[3];
  h.P[3] := FBuf[4];
  kind := FKind;
  if kind = zhkHex then
  begin
    FState := zrsHexTail;
    FTailData := h.FrameType in [ZDATA, ZFILE, ZSINIT, ZCOMMAND];
  end
  else if h.FrameType in [ZDATA, ZFILE, ZSINIT, ZCOMMAND] then
    ExpectData(kind = zhkBin32)          { before the event: it may DropData }
  else
    FState := zrsSeek;
  FCount := 0;
  if Assigned(FOnHeader) then
    FOnHeader(h, kind);
  FGarbage := 0;
end;

procedure TZmReader.DataFailed;
begin
  FState := zrsSeek;
  FEscaped := False;
  FDataLen := 0;
  if Assigned(FOnData) then
    FOnData('', 0, False);
end;

procedure TZmReader.DataByte(B: Byte);
begin
  if FDataLen >= FMaxSubpacket then
  begin
    DataFailed;
    Exit;
  end;
  if FDataLen >= Length(FData) then
    SetLength(FData, Length(FData) * 2 + 1024);
  Inc(FDataLen);
  FData[FDataLen] := AnsiChar(B);
end;

procedure TZmReader.DataDone;
var
  ok: Boolean;
  crc16: Word;
  crc32: Cardinal;
  e: Byte;
  s: RawByteString;
begin
  e := FEnd;
  if FDataCrc32 then
  begin
    if FDataLen > 0 then
      crc32 := ZmCrc32($FFFFFFFF, @FData[1], FDataLen)
    else
      crc32 := $FFFFFFFF;
    crc32 := not ZmCrc32(crc32, @e, 1);
    ok := (FBuf[0] = crc32 and $FF) and (FBuf[1] = (crc32 shr 8) and $FF)
      and (FBuf[2] = (crc32 shr 16) and $FF) and (FBuf[3] = crc32 shr 24);
  end
  else
  begin
    if FDataLen > 0 then
      crc16 := ZmCrc16(0, @FData[1], FDataLen)
    else
      crc16 := 0;
    crc16 := ZmCrc16(crc16, @e, 1);
    ok := crc16 = (Word(FBuf[0]) shl 8) or FBuf[1];
  end;
  s := Copy(FData, 1, FDataLen);
  FDataLen := 0;
  if ok and (e in [ZCRCG, ZCRCQ]) then
    FState := zrsData                    { the next subpacket follows }
  else
    FState := zrsSeek;
  if Assigned(FOnData) then
    FOnData(s, e, ok);
end;

procedure TZmReader.Feed(B: Byte);
begin
  { five CANs in a row: the other side aborts (in any state) }
  if B = ZDLE then
  begin
    Inc(FCanRun);
    if FCanRun = 5 then
    begin
      FState := zrsSeek;
      FEscaped := False;
      FDataLen := 0;
      if Assigned(FOnCancel) then
        FOnCancel(Self);
      Exit;
    end;
  end
  else
    FCanRun := 0;
  { unescaped XON / XOFF: flow control somewhere on the way, never data }
  if B in [$11, $13, $91, $93] then
    Exit;
  Step(B);
end;

{ after a hex header's CR LF: its data (CRC-16), or the next header }
procedure TZmReader.EndHexTail;
begin
  if FTailData then
    ExpectData(False)
  else
    FState := zrsSeek;
end;

procedure TZmReader.Step(B: Byte);
var
  v: Integer;
begin
  case FState of
    zrsSeek:
      if B = ZPAD then
        FState := zrsPad
      else
        Inc(FGarbage);
    zrsPad:
      if B = ZDLE then
        FState := zrsPadDle
      else if B <> ZPAD then
        Garbage;
    zrsPadDle:
      begin
        FCount := 0;
        FEscaped := False;
        FHexHigh := -1;
        case B of
          ZHEX:
            begin
              FKind := zhkHex;
              FNeed := 7;
              FState := zrsHex;
            end;
          ZBIN:
            begin
              FKind := zhkBin16;
              FNeed := 7;
              FState := zrsBin;
            end;
          ZBIN32:
            begin
              FKind := zhkBin32;
              FNeed := 9;
              FState := zrsBin;
            end;
        else
          Garbage;
        end;
      end;
    zrsHex:
      begin
        case Chr(B) of
          '0'..'9': v := B - Ord('0');
          'a'..'f': v := B - Ord('a') + 10;
          'A'..'F': v := B - Ord('A') + 10;
        else
          v := -1;
        end;
        if v < 0 then
        begin
          Garbage;
          Exit;
        end;
        if FHexHigh < 0 then
          FHexHigh := v
        else
        begin
          FBuf[FCount] := (FHexHigh shl 4) or v;
          FHexHigh := -1;
          Inc(FCount);
          if FCount = FNeed then
            HeaderDone;
        end;
      end;
    zrsHexTail:
      { CR, LF with or without the high bit (XON is dropped above); anything else
        starts the next search }
      if ((B and $7F) in [$0D, $0A]) and (FCount < 2) then
      begin
        Inc(FCount);
        if FCount >= 2 then
          EndHexTail;
      end
      else
      begin
        EndHexTail;
        Step(B);                         { the first byte of what follows }
      end;
    zrsBin:
      begin
        if FEscaped then
        begin
          FEscaped := False;
          case B of
            ZRUB0: B := $7F;
            ZRUB1: B := $FF;
          else
            if (B and $60) = $40 then
              B := B xor $40
            else
            begin
              Garbage;                   { a frame end or a bad escape inside a header }
              Exit;
            end;
          end;
        end
        else if B = ZDLE then
        begin
          FEscaped := True;
          Exit;
        end;
        FBuf[FCount] := B;
        Inc(FCount);
        if FCount = FNeed then
          HeaderDone;
      end;
    zrsData:
      if FEscaped then
      begin
        FEscaped := False;
        case B of
          ZCRCE, ZCRCG, ZCRCQ, ZCRCW:
            begin
              FEnd := B;
              FCount := 0;
              if FDataCrc32 then FNeed := 4 else FNeed := 2;
              FState := zrsDataCrc;
            end;
          ZRUB0: DataByte($7F);
          ZRUB1: DataByte($FF);
        else
          if (B and $60) = $40 then
            DataByte(B xor $40)
          else
            DataFailed;
        end;
      end
      else if B = ZDLE then
        FEscaped := True
      else
        DataByte(B);
    zrsDataCrc:
      if FEscaped then
      begin
        FEscaped := False;
        case B of
          ZRUB0: B := $7F;
          ZRUB1: B := $FF;
        else
          if (B and $60) = $40 then
            B := B xor $40
          else
          begin
            DataFailed;
            Exit;
          end;
        end;
        FBuf[FCount] := B;
        Inc(FCount);
        if FCount = FNeed then
          DataDone;
      end
      else if B = ZDLE then
        FEscaped := True
      else
      begin
        FBuf[FCount] := B;
        Inc(FCount);
        if FCount = FNeed then
          DataDone;
      end;
  end;
end;

function TZmReader.Push(AData: PByte; ACount: Integer): Integer;
var
  i: Integer;
begin
  FStopped := False;
  for i := 0 to ACount - 1 do
  begin
    Feed(AData[i]);
    if FStopped then
    begin
      FStopped := False;
      Exit(i + 1);
    end;
  end;
  Result := ACount;
end;

initialization
  BuildCrcTables;
end.
