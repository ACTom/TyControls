unit tyControls.RichEdit.TextIO;

{ Plain text files for TTyRichEdit's document: reading finds the encoding (a BOM, then valid
  UTF-8, then an ANSI code page), the BOM and the majority line break, and keeps them on the
  document; writing puts the text back in that encoding. A file opened and saved without a
  change comes back byte for byte, also where its bytes are not text in its encoding.

  UTF-8 is not converted: the file's bytes, read once into one buffer, are the text storage's
  original buffer (an invalid byte is a character of its own there and goes back out as it
  is). Every other encoding is converted to UTF-8 a chunk at a time, straight from the
  stream, so neither the whole file nor a second copy of the text is ever held. The
  conversion is a table per code page (built once from LazUtils' LConvEncoding tables, which
  are the same on every platform) and a tight loop over it, which also finds the text's
  pieces (paragraphs) as it writes them, so a converted file is decoded and indexed in one
  pass, with no scan of the converted text afterwards (TTyRichText.CreateScanned).

  A byte the conversion cannot carry as text - one that is no character in the code page, a
  lone surrogate or an odd last byte in UTF-16, or one of two byte sequences that read as
  the same character (only the first of them in byte order is written for that character) -
  is escaped: byte b becomes the two bytes F8+(b shr 6), 80+(b and 3F). Neither can start a
  UTF-8 character, so the storage keeps them as two characters of one byte each, and nothing
  decoded or typed can look like them; writing turns the pair back into b.

  Line breaks: the stored separators are written as they are (the reader stores CR, LF and
  CRLF as found); the model makes every inserted break the document's DominantLineBreak, so
  writing never has to choose one. }

{$mode objfpc}{$H+}
{$inline on}

interface

uses
  Classes, SysUtils, tyControls.RichEdit.Text, tyControls.RichEdit.Model;

const
  { Bytes a converted file is read in at a time (a lead byte, a surrogate or a CR at the
    end of one is carried to the next; tests put them there). }
  TyRichTextChunkSize = 1 shl 20;

type
  ETyRichTextIO = class(Exception);

{ Replaces ADoc's content with the text in AStream from its position to its end (the stream
  must be able to seek), as loading, not as a change: the history goes and Modified is False
  (TTyRichDocBuilder.ReplaceText). teAuto: a UTF-8 or UTF-16 BOM decides; else valid UTF-8
  (pure ASCII and an empty stream included) is UTF-8; else it is ANSI in ACodePage. A forced
  UTF-8 or UTF-16 skips (and records) its own BOM when there is one. teAnsi and the ANSI
  fallback: ACodePage, 0 meaning the system's ANSI code page - and where that is UTF-8
  itself (Linux, macOS) or one this unit cannot convert, 1252. Records SourceEncoding,
  SourceCodePage (teAnsi only), SourceHasBom and DominantLineBreak on ADoc. Raises
  ETyRichTextIO for a code page it cannot convert, ETyRichModel while ADoc runs a command or
  is inside BeginUpdate .. EndUpdate. }
procedure TyRichLoadText(ADoc: TTyRichDocument; AStream: TStream;
  AEncoding: TTyTextEncoding = teAuto; ACodePage: Integer = 0);
{ Writes ADoc's text to AStream in ADoc's SourceEncoding (its BOM when SourceHasBom), with
  the line breaks as they are stored. Streams through a fixed buffer. A character the code
  page has no bytes for is written '?' (ANSI); a stored byte that is not UTF-8 is written as
  it is (UTF-8), '?' (ANSI) or U+FFFD (UTF-16), unless it is an escape (see the unit
  comment). }
procedure TyRichSaveText(ADoc: TTyRichDocument; AStream: TStream);

{ The code page teAnsi uses for ACodePage: ACodePage itself, or for 0 the system's ANSI code
  page (1252 where that is UTF-8 or not supported). }
function TyRichAnsiCodePage(ACodePage: Integer = 0): Integer;
{ Code pages TyRichLoadText/TyRichSaveText convert: 437, 850, 852, 865, 866, 874, 932, 936,
  949, 950, 1250-1258, 10000 (Mac Roman), 20866 (KOI8-R), 28591-28599, 28600, 28603-28606
  (ISO 8859). }
function TyRichCodePageSupported(ACodePage: Integer): Boolean;
{ Strict: no overlongs, no surrogates, nothing above U+10FFFF, nothing cut short. }
function TyRichIsUtf8(ABuf: PByte; ACount: PtrInt): Boolean;

{ For the RTF reader, which decodes bytes one at a time by the code page of the font in
  effect: the code page's table (the one text files are converted with, the same on every
  platform), found once; nil when the code page is not supported. }
function TyRichCodePageTable(ACodePage: Integer): Pointer;
{ AByte starts a two-byte character in the table's code page. }
function TyRichCodePageIsLead(ATable: Pointer; AByte: Byte): Boolean;
{ The code point of the single byte ALead (ATrail < 0) or of the pair ALead ATrail; 0 when it
  is no character. Unlike a text file, where only the first of two sequences that read as
  the same character counts as text, both read as that character here. }
function TyRichCodePageChar(ATable: Pointer; ALead: Byte; ATrail: Integer): Cardinal;
{ For the RTF index scan, which only counts characters and must not make a call per byte:
  the table's 256 byte classes (0 ASCII, 1 a character of its own, 2 a lead byte, 3 no
  character the table knows - ask TyRichCodePageChar), and its pairs as bits (bit
  (lead shl 8) or trail set: the pair is a character the table knows; clear: ask
  TyRichCodePageChar), nil for a single-byte code page. Valid while the table is. }
function TyRichCodePageClasses(ATable: Pointer): PByte;
function TyRichCodePagePairs(ATable: Pointer): PByte;

implementation

uses
  {$IFDEF MSWINDOWS}Windows,{$ENDIF} LConvEncoding;

const
  ChunkSize = TyRichTextChunkSize;
  SaveBufSize = 256 * 1024;   // the saver's working buffer
  // the most UTF-8 bytes one input byte turns into (a high single byte in a code page: 3;
  // an escaped byte: 2), plus room for the decoders' 3-byte stores
  MaxGrowth = 3;
  StoreSlack = 8;
  High8 = QWord($8080808080808080);

type
  TCpConv = function(const s: string): string;

  { One code page, both ways. Cls per byte: 0 ASCII (itself), 1 a character of its own
    (Single), 2 the lead byte of a pair (Pair), 3 no text (escaped). Single and Pair hold
    the character's UTF-8 bytes in the low 24 bits and their count above; a Pair entry of 0
    is no character. Rev: the bytes a BMP code point is written as (a single byte, or
    lead shl 8 or trail); 0 for none. A sequence whose character Rev does not give back
    those same bytes is not text either (it is escaped), so what is read always writes back
    as it was. }
  TCodePageTable = class
  public
    CodePage: Integer;
    Cls: array[0..255] of Byte;
    Single: array[0..255] of Cardinal;
    Pair: array of Cardinal;
    Rev: array of Word;
    PairBits: array of Byte;   // bit (lead shl 8) or trail: Pair has a character (built on first use)
  end;

  TTextIOBuilder = class(TTyRichDocBuilder)
  public
    class procedure Replace(ADoc: TTyRichDocument; AText: TTyRichText;
      AEncoding: TTyTextEncoding; ACodePage: Integer; AHasBom: Boolean);
  end;

  { The converted text as it grows: Data's length is its capacity. }
  TOutBuf = record
    Data: TBytes;
    Used: Int64;
  end;

  TTextSaver = class
  private
    FText: TTyRichText;
    FStream: TStream;
    FEnc: TTyTextEncoding;
    FTable: TCodePageTable;
    FBuf: PByte;
    FLen: Integer;
    FPos: Int64;               // characters written
    FLazyChars: Int64;         // the lazy run ForEachRun stopped at (0: none)
    FPrefix: Integer;          // an escape's first byte waiting for the next run, or -1
    procedure Flush;
    procedure Room(AMore: Integer); inline;
    procedure PutByte(B: Byte); inline;
    procedure PutUnit(U: Cardinal);
    procedure PutUnknown;
    procedure PutOther(var P: PByte; E: PByte);
    procedure Put(P: PByte; ACount: PtrInt);
    procedure Run(const ARun: TTyRichByteRun; var AContinue: Boolean);
  public
    constructor Create(AText: TTyRichText; AStream: TStream; AEnc: TTyTextEncoding;
      ATable: TCodePageTable);
    destructor Destroy; override;
    procedure Save;
  end;

var
  Tables: TFPList;

{ ---- UTF-8 ---- }

{$PUSH}{$Q-}{$R-}
{ True when every sequence in the bytes is valid; one cut by the end counts as valid when
  AAllowCut (more of the file follows) and what there is of it fits. }
function ValidUtf8(P: PByte; ACount: PtrInt; AAllowCut: Boolean): Boolean;
var
  e: PByte;
  b, b1: Byte;
  n, k: PtrInt;
begin
  e := P + ACount;
  while P < e do
  begin
    while (e - P >= 8) and (unaligned(PQWord(P)^) and High8 = 0) do Inc(P, 8);
    if P >= e then Break;
    b := P^;
    if b < $80 then
    begin
      Inc(P);
      Continue;
    end;
    if b < $C2 then Exit(False);
    if b < $E0 then n := 2
    else if b < $F0 then n := 3
    else if b < $F5 then n := 4
    else Exit(False);
    if e - P < n then
    begin
      if not AAllowCut then Exit(False);
      for k := 1 to e - P - 1 do
        if P[k] and $C0 <> $80 then Exit(False);
      if e - P >= 2 then
      begin
        b1 := P[1];
        if ((b = $E0) and (b1 < $A0)) or ((b = $ED) and (b1 > $9F)) or
           ((b = $F0) and (b1 < $90)) or ((b = $F4) and (b1 > $8F)) then Exit(False);
      end;
      Exit(True);
    end;
    b1 := P[1];
    if b1 and $C0 <> $80 then Exit(False);
    if n >= 3 then
    begin
      if P[2] and $C0 <> $80 then Exit(False);
      if n = 3 then
      begin
        if ((b = $E0) and (b1 < $A0)) or ((b = $ED) and (b1 > $9F)) then Exit(False);
      end
      else
      begin
        if P[3] and $C0 <> $80 then Exit(False);
        if ((b = $F0) and (b1 < $90)) or ((b = $F4) and (b1 > $8F)) then Exit(False);
      end;
    end;
    Inc(P, n);
  end;
  Result := True;
end;

{ The code point of the valid UTF-8 sequence at P and its length, or 0 when the byte there
  starts none (the same strict rules as ValidUtf8). }
function DecodeUtf8(P: PByte; AAvail: PtrInt; out ACode: Cardinal): Integer; inline;
var
  b, b1: Byte;
begin
  b := P^;
  Result := 0;
  ACode := 0;
  if b < $C2 then Exit;
  if b < $E0 then
  begin
    if (AAvail >= 2) and (P[1] and $C0 = $80) then
    begin
      ACode := (Cardinal(b and $1F) shl 6) or (P[1] and $3F);
      Result := 2;
    end;
    Exit;
  end;
  if b < $F0 then
  begin
    if AAvail < 3 then Exit;
    b1 := P[1];
    if (b1 and $C0 <> $80) or (P[2] and $C0 <> $80) or ((b = $E0) and (b1 < $A0)) or
       ((b = $ED) and (b1 > $9F)) then Exit;
    ACode := (Cardinal(b and $0F) shl 12) or (Cardinal(b1 and $3F) shl 6) or (P[2] and $3F);
    Exit(3);
  end;
  if b < $F5 then
  begin
    if AAvail < 4 then Exit;
    b1 := P[1];
    if (b1 and $C0 <> $80) or (P[2] and $C0 <> $80) or (P[3] and $C0 <> $80) or
       ((b = $F0) and (b1 < $90)) or ((b = $F4) and (b1 > $8F)) then Exit;
    ACode := (Cardinal(b and $07) shl 18) or (Cardinal(b1 and $3F) shl 12) or
      (Cardinal(P[2] and $3F) shl 6) or (P[3] and $3F);
    Exit(4);
  end;
end;
{$POP}

function TyRichIsUtf8(ABuf: PByte; ACount: PtrInt): Boolean;
begin
  Result := ValidUtf8(ABuf, ACount, False);
end;

{ ---- code pages ---- }

function ConvOf(ACodePage: Integer): TCpConv;
begin
  case ACodePage of
    437: Result := @CP437ToUTF8;
    850: Result := @CP850ToUTF8;
    852: Result := @CP852ToUTF8;
    865: Result := @CP865ToUTF8;
    866: Result := @CP866ToUTF8;
    874: Result := @CP874ToUTF8;
    932: Result := @CP932ToUTF8;
    936: Result := @CP936ToUTF8;
    949: Result := @CP949ToUTF8;
    950: Result := @CP950ToUTF8;
    1250: Result := @CP1250ToUTF8;
    1251: Result := @CP1251ToUTF8;
    1252: Result := @CP1252ToUTF8;
    1253: Result := @CP1253ToUTF8;
    1254: Result := @CP1254ToUTF8;
    1255: Result := @CP1255ToUTF8;
    1256: Result := @CP1256ToUTF8;
    1257: Result := @CP1257ToUTF8;
    1258: Result := @CP1258ToUTF8;
    10000: Result := @MacintoshToUTF8;
    20866: Result := @KOI8RToUTF8;
    28591: Result := @ISO_8859_1ToUTF8;
    28592: Result := @ISO_8859_2ToUTF8;
    28593: Result := @ISO_8859_3ToUTF8;
    28594: Result := @ISO_8859_4ToUTF8;
    28595: Result := @ISO_8859_5ToUTF8;
    28597: Result := @ISO_8859_7ToUTF8;
    28599: Result := @ISO_8859_9ToUTF8;
    28600: Result := @ISO_8859_10ToUTF8;
    28603: Result := @ISO_8859_13ToUTF8;
    28604: Result := @ISO_8859_14ToUTF8;
    28605: Result := @ISO_8859_15ToUTF8;
    28606: Result := @ISO_8859_16ToUTF8;
  else
    Result := nil;
  end;
end;

function TyRichCodePageSupported(ACodePage: Integer): Boolean;
begin
  Result := ConvOf(ACodePage) <> nil;
end;

function IsDoubleByte(ACodePage: Integer): Boolean;
begin
  Result := (ACodePage = 932) or (ACodePage = 936) or (ACodePage = 949) or (ACodePage = 950);
end;

{ One character's UTF-8 as a table entry: 0 when S is not exactly one character of at most
  three bytes (LConvEncoding gives '' - or '?' in its replace mode - for no character). }
function PackChar(const S: string; out ACode: Cardinal): Cardinal;
var
  n: Integer;
begin
  Result := 0;
  ACode := 0;
  if (S = '') or (S = '?') or (Length(S) > 3) then Exit;
  n := DecodeUtf8(PByte(PChar(S)), Length(S), ACode);
  if (n <> Length(S)) or (ACode < $80) then Exit;
  Result := Byte(S[1]) or (Cardinal(Length(S)) shl 24);
  if Length(S) > 1 then Result := Result or (Cardinal(Byte(S[2])) shl 8);
  if Length(S) > 2 then Result := Result or (Cardinal(Byte(S[3])) shl 16);
end;

function CodeOf(AEntry: Cardinal): Cardinal;
var
  s: array[0..3] of Byte;
begin
  s[0] := Byte(AEntry);
  s[1] := Byte(AEntry shr 8);
  s[2] := Byte(AEntry shr 16);
  s[3] := 0;
  if DecodeUtf8(@s[0], AEntry shr 24, Result) = 0 then Result := 0;
end;

{ Asks LConvEncoding about every byte and every pair once. }
function BuildTable(ACodePage: Integer): TCodePageTable;
var
  conv: TCpConv;
  dbl, any: Boolean;
  b, t, i: Integer;
  v, code: Cardinal;
begin
  conv := ConvOf(ACodePage);
  dbl := IsDoubleByte(ACodePage);
  Result := TCodePageTable.Create;
  Result.CodePage := ACodePage;
  SetLength(Result.Rev, 65536);
  if dbl then SetLength(Result.Pair, 65536);
  for b := 0 to 127 do Result.Cls[b] := 0;
  for b := 128 to 255 do
  begin
    v := PackChar(conv(Chr(b)), code);
    if v <> 0 then
    begin
      Result.Cls[b] := 1;
      Result.Single[b] := v;
    end
    else if dbl then
      Result.Cls[b] := 2
    else
      Result.Cls[b] := 3;
  end;
  if dbl then
    for b := 128 to 255 do
      if Result.Cls[b] = 2 then
      begin
        any := False;
        for t := $40 to $FF do
        begin
          v := PackChar(conv(Chr(b) + Chr(t)), code);
          if v <> 0 then
          begin
            Result.Pair[(b shl 8) or t] := v;
            any := True;
          end;
        end;
        if not any then Result.Cls[b] := 3;
      end;
  // the way back: the first sequence in byte order for each character
  for b := 128 to 255 do
    if Result.Cls[b] = 1 then
    begin
      code := CodeOf(Result.Single[b]);
      if (code <= $FFFF) and (Result.Rev[code] = 0) then Result.Rev[code] := b;
    end;
  if dbl then
    for i := $8000 to $FFFF do
      if Result.Pair[i] <> 0 then
      begin
        code := CodeOf(Result.Pair[i]);
        if (code <= $FFFF) and (Result.Rev[code] = 0) then Result.Rev[code] := i;
      end;
  // what does not come back as it was is no text
  for b := 128 to 255 do
    if (Result.Cls[b] = 1) and (Result.Rev[CodeOf(Result.Single[b])] <> b) then
      Result.Cls[b] := 3;
  if dbl then
    for i := $8000 to $FFFF do
      if (Result.Pair[i] <> 0) and (Result.Rev[CodeOf(Result.Pair[i])] <> i) then
        Result.Pair[i] := 0;
end;

{ Built on first use and kept; the UI thread's (not locked). }
function TableFor(ACodePage: Integer): TCodePageTable;
var
  i: Integer;
begin
  if not TyRichCodePageSupported(ACodePage) then
    raise ETyRichTextIO.CreateFmt('Code page %d is not supported', [ACodePage]);
  if Tables = nil then Tables := TFPList.Create;
  for i := 0 to Tables.Count - 1 do
    if TCodePageTable(Tables[i]).CodePage = ACodePage then
      Exit(TCodePageTable(Tables[i]));
  Result := BuildTable(ACodePage);
  Tables.Add(Result);
end;

function SystemAnsiCodePage: Integer;
{$IFNDEF MSWINDOWS}
var
  e: string;
{$ENDIF}
begin
  {$IFDEF MSWINDOWS}
  Result := GetACP;
  {$ELSE}
  // the locale's charset, as LConvEncoding reads it from LANG (macOS: always UTF-8)
  e := LowerCase(GetDefaultTextEncoding);
  if (e = 'gbk') or (e = 'gb2312') or (e = 'euccn') then Result := 936
  else if e = 'big5' then Result := 950
  else if (e = 'sjis') or (e = 'shiftjis') or (e = 'shift_jis') then Result := 932
  else if (e = 'euckr') or (e = 'uhc') then Result := 949
  else if e = 'koi8r' then Result := 20866
  else if e = 'macintosh' then Result := 10000
  else if (Copy(e, 1, 2) = 'cp') and (StrToIntDef(Copy(e, 3, MaxInt), 0) > 0) then
    Result := StrToInt(Copy(e, 3, MaxInt))
  else if (Copy(e, 1, 7) = 'iso8859') and (StrToIntDef(Copy(e, 8, MaxInt), 0) > 0) then
    Result := 28590 + StrToInt(Copy(e, 8, MaxInt))
  else
    Result := 65001;
  {$ENDIF}
end;

function TyRichAnsiCodePage(ACodePage: Integer): Integer;
begin
  if ACodePage <> 0 then Exit(ACodePage);
  Result := SystemAnsiCodePage;
  // a UTF-8 system has no ANSI code page; text that is not UTF-8 there is most likely
  // Windows Western
  if (Result = 65001) or not TyRichCodePageSupported(Result) then Result := 1252;
end;

function TyRichCodePageTable(ACodePage: Integer): Pointer;
begin
  if not TyRichCodePageSupported(ACodePage) then Exit(nil);
  Result := TableFor(ACodePage);
end;

function TyRichCodePageIsLead(ATable: Pointer; AByte: Byte): Boolean;
begin
  Result := TCodePageTable(ATable).Cls[AByte] = 2;
end;

function TyRichCodePageClasses(ATable: Pointer): PByte;
begin
  Result := @TCodePageTable(ATable).Cls[0];
end;

function TyRichCodePagePairs(ATable: Pointer): PByte;
var
  t: TCodePageTable;
  i: Integer;
begin
  t := TCodePageTable(ATable);
  if t.Pair = nil then Exit(nil);
  // 8 KB instead of the 256 KB of Pair: counting pairs stays in the first-level cache
  if t.PairBits = nil then
  begin
    SetLength(t.PairBits, 65536 div 8);
    for i := 0 to 65535 do
      if t.Pair[i] <> 0 then
        t.PairBits[i shr 3] := t.PairBits[i shr 3] or (1 shl (i and 7));
  end;
  Result := @t.PairBits[0];
end;

function TyRichCodePageChar(ATable: Pointer; ALead: Byte; ATrail: Integer): Cardinal;
var
  t: TCodePageTable;
  e, code: Cardinal;
  s: string;
begin
  t := TCodePageTable(ATable);
  if ATrail < 0 then
  begin
    case t.Cls[ALead] of
      0: Exit(ALead);
      1: Exit(CodeOf(t.Single[ALead]));
    end;
    s := Chr(ALead);
  end
  else
  begin
    if ATrail > 255 then Exit(0);
    if t.Pair <> nil then
    begin
      e := t.Pair[(ALead shl 8) or ATrail];
      if e <> 0 then Exit(CodeOf(e));
    end;
    s := Chr(ALead) + Chr(ATrail);
  end;
  // the table leaves out what does not write back as it was read (the second of two
  // sequences for one character); ask the converter itself about that rare case
  Result := 0;
  if PackChar(ConvOf(t.CodePage)(s), code) <> 0 then Result := code;
end;

{ ---- reading ---- }

class procedure TTextIOBuilder.Replace(ADoc: TTyRichDocument; AText: TTyRichText;
  AEncoding: TTyTextEncoding; ACodePage: Integer; AHasBom: Boolean);
begin
  ReplaceText(ADoc, AText, AEncoding, ACodePage, AHasBom, TyRichMajorityLineBreak(
    AText.LoadedSeparators(rsCR), AText.LoadedSeparators(rsLF), AText.LoadedSeparators(rsCRLF)));
end;

procedure ReadInto(AStream: TStream; P: PByte; ACount: Int64);
var
  n: Longint;
begin
  while ACount > 0 do
  begin
    if ACount > 1 shl 29 then n := 1 shl 29 else n := ACount;
    AStream.ReadBuffer(P^, n);
    Inc(P, n);
    Dec(ACount, n);
  end;
end;

{ Room for ANeed more bytes. When it must grow, it grows to what the ratio so far says the
  whole text will need, so a file converts with about one growth and no big copy. }
procedure Reserve(var O: TOutBuf; ANeed, ALeftIn, AConsumedIn: Int64);
var
  cap: Int64;
begin
  if O.Used + ANeed <= Length(O.Data) then Exit;
  // ANeed is the worst case of one chunk, twice over: a projection a little short at the
  // end must not cost a growth (a copy of the whole text) per chunk
  cap := O.Used + 2 * ANeed;
  if AConsumedIn > 0 then
    Inc(cap, ALeftIn * O.Used div AConsumedIn + ALeftIn * O.Used div AConsumedIn div 32);
  SetLength(O.Data, cap);
end;

{$PUSH}{$Q-}{$R-}
{ The decoders write UTF-8 and find the text's pieces in the same pass, exactly as
  TTyRichText's load scan would find them in what they write (TTyRichText.CreateScanned):
  a piece ends with each separator, and without one where it reaches TyRichMaxPieceBytes.
  The decoded characters are all valid UTF-8; an escaped byte is two bytes that start no
  sequence, so two characters and two invalid bytes, as the scan counts them. }
type
  TScanState = record
    Text: TTyRichText;
    Start: Int64;          // where the piece being built starts in the output
    Chars: PtrInt;         // its characters so far
    Invalid: Int64;        // escaped bytes written: two each
  end;

{ Ends the piece at D: a separator piece (ASep, ACharsWithSep counted) or one cut at the
  size limit. }
procedure EndPiece(var S: TScanState; D: PByte; var APStart, ALim: PByte; AChars: PtrInt;
  ASep: TTyRichSeparator); inline;
begin
  S.Text.AppendScanned(D - APStart, AChars, ASep);
  APStart := D;
  ALim := D + TyRichMaxPieceBytes;
end;

{ Converts ACount bytes of the code page at Src to UTF-8 at D and returns how many it took:
  all of them when ALast, else it may leave a lead byte or a CR whose partner is in the next
  chunk. ABase: the output buffer, which S.Start is relative to. }
function DecodeAnsiChunk(T: TCodePageTable; Src: PByte; ACount: PtrInt; ALast: Boolean;
  ABase: PByte; var D: PByte; var S: TScanState): PtrInt;
const
  Below14 = QWord($0E0E0E0E0E0E0E0E);
var
  p, q, e, stop, d0, cls, pstart, lim: PByte;
  single, pair: PCardinal;
  b: Byte;
  v: Cardinal;
  x: QWord;
  chars: PtrInt;
  sep: TTyRichSeparator;
begin
  // the tables as plain pointers, so the loop reads no object or array header
  cls := @T.Cls[0];
  single := @T.Single[0];
  pair := PCardinal(T.Pair);
  p := Src;
  e := Src + ACount;
  d0 := D;
  pstart := ABase + S.Start;
  lim := pstart + TyRichMaxPieceBytes;
  chars := S.Chars;
  while p < e do
  begin
    b := p^;
    if (b > 13) and (b < $80) then
    begin
      // printable ASCII: one byte (a space between words) costs one store; a run goes
      // eight at a time, up to the piece limit
      d0^ := b;
      Inc(d0);
      Inc(p);
      Inc(chars);
      if (p < e) and (p^ > 13) and (p^ < $80) and (d0 < lim) then
      begin
        if lim - d0 < e - p then stop := p + (lim - d0) else stop := e;
        q := p;
        while stop - p >= 8 do
        begin
          x := unaligned(PQWord(p)^);
          if (x or ((x - Below14) and not x)) and High8 <> 0 then Break;
          PQWord(d0)^ := x;
          Inc(p, 8);
          Inc(d0, 8);
        end;
        while (p < stop) and (p^ > 13) and (p^ < $80) do
        begin
          d0^ := p^;
          Inc(p);
          Inc(d0);
        end;
        Inc(chars, p - q);
      end;
      if d0 >= lim then
      begin
        EndPiece(S, d0, pstart, lim, chars, rsNone);
        chars := 0;
      end;
      Continue;
    end;
    if b >= $80 then
    begin
      case cls[b] of
        2:
          if p + 1 < e then
          begin
            v := pair[(Cardinal(b) shl 8) or p[1]];
            if v <> 0 then
            begin
              // three bytes stored whatever the count: the buffer has the slack
              d0[0] := Byte(v);
              d0[1] := Byte(v shr 8);
              d0[2] := Byte(v shr 16);
              Inc(d0, v shr 24);
              Inc(p, 2);
              Inc(chars);
              if d0 >= lim then
              begin
                EndPiece(S, d0, pstart, lim, chars, rsNone);
                chars := 0;
              end;
              Continue;
            end;
          end
          else if not ALast then
            Break;
        1:
          begin
            v := single[b];
            d0[0] := Byte(v);
            d0[1] := Byte(v shr 8);
            d0[2] := Byte(v shr 16);
            Inc(d0, v shr 24);
            Inc(p);
            Inc(chars);
            if d0 >= lim then
            begin
              EndPiece(S, d0, pstart, lim, chars, rsNone);
              chars := 0;
            end;
            Continue;
          end;
      end;
      // no text: escaped, two characters (the limit may fall between them)
      d0^ := $F8 or (b shr 6);
      Inc(d0);
      Inc(chars);
      if d0 >= lim then
      begin
        EndPiece(S, d0, pstart, lim, chars, rsNone);
        chars := 0;
      end;
      d0^ := $80 or (b and $3F);
      Inc(d0);
      Inc(chars);
      if d0 >= lim then
      begin
        EndPiece(S, d0, pstart, lim, chars, rsNone);
        chars := 0;
      end;
      Inc(S.Invalid, 2);
      Inc(p);
      Continue;
    end;
    // b <= 13: a line break, or a control character
    if b = 10 then
    begin
      d0^ := 10;
      Inc(d0);
      Inc(p);
      sep := rsLF;
    end
    else if b = 13 then
    begin
      if p + 1 < e then
      begin
        if p[1] = 10 then
        begin
          d0[0] := 13;
          d0[1] := 10;
          Inc(d0, 2);
          Inc(p, 2);
          sep := rsCRLF;
        end
        else
        begin
          d0^ := 13;
          Inc(d0);
          Inc(p);
          sep := rsCR;
        end;
      end
      else if not ALast then
        Break   // its LF may be the next chunk's first byte
      else
      begin
        d0^ := 13;
        Inc(d0);
        Inc(p);
        sep := rsCR;
      end;
    end
    else
    begin
      d0^ := b;
      Inc(d0);
      Inc(p);
      Inc(chars);
      if d0 >= lim then
      begin
        EndPiece(S, d0, pstart, lim, chars, rsNone);
        chars := 0;
      end;
      Continue;
    end;
    EndPiece(S, d0, pstart, lim, chars + 1, sep);
    chars := 0;
  end;
  D := d0;
  S.Start := pstart - ABase;
  S.Chars := chars;
  Result := p - Src;
end;

procedure PutCode(ACode: Cardinal; var D: PByte); inline;
begin
  if ACode < $80 then
  begin
    D^ := ACode;
    Inc(D);
  end
  else if ACode < $800 then
  begin
    D[0] := $C0 or (ACode shr 6);
    D[1] := $80 or (ACode and $3F);
    Inc(D, 2);
  end
  else if ACode < $10000 then
  begin
    D[0] := $E0 or (ACode shr 12);
    D[1] := $80 or ((ACode shr 6) and $3F);
    D[2] := $80 or (ACode and $3F);
    Inc(D, 3);
  end
  else
  begin
    D[0] := $F0 or (ACode shr 18);
    D[1] := $80 or ((ACode shr 12) and $3F);
    D[2] := $80 or ((ACode shr 6) and $3F);
    D[3] := $80 or (ACode and $3F);
    Inc(D, 4);
  end;
end;

{ The same for UTF-16: it may leave an odd last byte, a high surrogate whose partner is in
  the next chunk, or a CR whose LF may be there. }
function DecodeUtf16Chunk(ABig: Boolean; Src: PByte; ACount: PtrInt; ALast: Boolean;
  ABase: PByte; var D: PByte; var S: TScanState): PtrInt;
var
  p, e, d0, pstart, lim: PByte;
  u, u2: Cardinal;
  chars: PtrInt;
  k, nesc: Integer;
  esc: array[0..3] of Byte;
  sep: TTyRichSeparator;
begin
  p := Src;
  e := Src + ACount;
  d0 := D;
  pstart := ABase + S.Start;
  lim := pstart + TyRichMaxPieceBytes;
  chars := S.Chars;
  while e - p >= 2 do
  begin
    if ABig then u := (Cardinal(p[0]) shl 8) or p[1] else u := p[0] or (Cardinal(p[1]) shl 8);
    nesc := 0;
    if (u > 13) and ((u < $D800) or (u > $DFFF)) then
    begin
      PutCode(u, d0);
      Inc(p, 2);
    end
    else if u = 10 then
    begin
      d0^ := 10;
      Inc(d0);
      Inc(p, 2);
      EndPiece(S, d0, pstart, lim, chars + 1, rsLF);
      chars := 0;
      Continue;
    end
    else if u = 13 then
    begin
      if e - p < 4 then
      begin
        if not ALast then Break;   // its LF may be in the next chunk
        u2 := 0;
      end
      else if ABig then u2 := (Cardinal(p[2]) shl 8) or p[3]
      else u2 := p[2] or (Cardinal(p[3]) shl 8);
      if u2 = 10 then
      begin
        d0[0] := 13;
        d0[1] := 10;
        Inc(d0, 2);
        Inc(p, 4);
        sep := rsCRLF;
      end
      else
      begin
        d0^ := 13;
        Inc(d0);
        Inc(p, 2);
        sep := rsCR;
      end;
      EndPiece(S, d0, pstart, lim, chars + 1, sep);
      chars := 0;
      Continue;
    end
    else if u <= 13 then
    begin
      d0^ := u;
      Inc(d0);
      Inc(p, 2);
    end
    else if u <= $DBFF then
    begin
      if e - p < 4 then
      begin
        if not ALast then Break;
        u2 := 0;
      end
      else if ABig then u2 := (Cardinal(p[2]) shl 8) or p[3]
      else u2 := p[2] or (Cardinal(p[3]) shl 8);
      if (u2 >= $DC00) and (u2 <= $DFFF) then
      begin
        PutCode($10000 + ((u - $D800) shl 10) + (u2 - $DC00), d0);
        Inc(p, 4);
      end
      else
      begin
        // a lone high surrogate: no character, its two bytes travel escaped
        esc[0] := p[0];
        esc[1] := p[1];
        nesc := 2;
        Inc(p, 2);
      end;
    end
    else
    begin
      esc[0] := p[0];
      esc[1] := p[1];
      nesc := 2;
      Inc(p, 2);
    end;
    if nesc = 0 then
    begin
      Inc(chars);
      if d0 >= lim then
      begin
        EndPiece(S, d0, pstart, lim, chars, rsNone);
        chars := 0;
      end;
      Continue;
    end;
    for k := 0 to nesc - 1 do
    begin
      d0^ := $F8 or (esc[k] shr 6);
      Inc(d0);
      Inc(chars);
      if d0 >= lim then
      begin
        EndPiece(S, d0, pstart, lim, chars, rsNone);
        chars := 0;
      end;
      d0^ := $80 or (esc[k] and $3F);
      Inc(d0);
      Inc(chars);
      if d0 >= lim then
      begin
        EndPiece(S, d0, pstart, lim, chars, rsNone);
        chars := 0;
      end;
      Inc(S.Invalid, 2);
    end;
  end;
  if (e - p = 1) and ALast then
  begin
    // an odd last byte
    d0^ := $F8 or (p^ shr 6);
    Inc(d0);
    Inc(chars);
    if d0 >= lim then
    begin
      EndPiece(S, d0, pstart, lim, chars, rsNone);
      chars := 0;
    end;
    d0^ := $80 or (p^ and $3F);
    Inc(d0);
    Inc(chars);
    Inc(S.Invalid, 2);
    Inc(p);
  end;
  D := d0;
  S.Start := pstart - ABase;
  S.Chars := chars;
  Result := p - Src;
end;
{$POP}

{ Converts ACount bytes of AStream, a chunk at a time, into one UTF-8 buffer just big enough,
  finding the text's pieces as it goes, and makes the text over it. ATable nil: UTF-16
  (ABig: big-endian). }
function ConvertStream(AStream: TStream; ACount: Int64; ATable: TCodePageTable;
  ABig: Boolean): TTyRichText;
var
  chunk: TBytes;
  o: TOutBuf;
  s: TScanState;
  left, consumed: Int64;
  carry, got, avail, took: PtrInt;
  d: PByte;
  last: Boolean;
begin
  chunk := nil;
  SetLength(chunk, ChunkSize + 4);
  o.Data := nil;
  o.Used := 0;
  s.Text := TTyRichText.CreateScanned;
  try
    s.Start := 0;
    s.Chars := 0;
    s.Invalid := 0;
    left := ACount;
    consumed := 0;
    carry := 0;
    repeat
      if left > ChunkSize then got := ChunkSize else got := left;
      if got > 0 then AStream.ReadBuffer(chunk[carry], got);
      Dec(left, got);
      avail := carry + got;
      last := left = 0;
      Reserve(o, Int64(avail) * MaxGrowth + StoreSlack, left, consumed);
      d := PByte(o.Data) + o.Used;
      if ATable <> nil then
        took := DecodeAnsiChunk(ATable, PByte(chunk), avail, last, PByte(o.Data), d, s)
      else
        took := DecodeUtf16Chunk(ABig, PByte(chunk), avail, last, PByte(o.Data), d, s);
      o.Used := d - PByte(o.Data);
      Inc(consumed, took);
      carry := avail - took;
      if carry > 0 then Move(chunk[took], chunk[0], carry);
    until last;
    chunk := nil;
    if o.Used > s.Start then
      s.Text.AppendScanned(o.Used - s.Start, s.Chars, rsNone);
    // the slack goes back before the text holds on to the buffer
    SetLength(o.Data, o.Used);
    s.Text.EndScanned(o.Data, s.Invalid);
  except
    s.Text.Free;
    raise;
  end;
  Result := s.Text;
end;

procedure TyRichLoadText(ADoc: TTyRichDocument; AStream: TStream;
  AEncoding: TTyTextEncoding; ACodePage: Integer);
var
  start, size: Int64;
  head: array[0..3] of Byte;
  probe: TBytes;
  buf: TBytes;
  n, bom, cp: Integer;
  enc: TTyTextEncoding;
  text: TTyRichText;
begin
  if (ADoc = nil) or (AStream = nil) then
    raise ETyRichTextIO.Create('TyRichLoadText needs a document and a stream');
  start := AStream.Position;
  size := AStream.Size - start;
  FillChar(head, SizeOf(head), 0);
  if size >= 4 then n := 4 else n := size;
  if n > 0 then AStream.ReadBuffer(head[0], n);
  bom := 0;
  enc := AEncoding;
  case AEncoding of
    teAuto, teUtf8, teUtf8Bom:
      if (n >= 3) and (head[0] = $EF) and (head[1] = $BB) and (head[2] = $BF) then
      begin
        enc := teUtf8Bom;
        bom := 3;
      end
      else if (AEncoding = teAuto) and (n >= 2) and (head[0] = $FF) and (head[1] = $FE) then
      begin
        enc := teUtf16LE;
        bom := 2;
      end
      else if (AEncoding = teAuto) and (n >= 2) and (head[0] = $FE) and (head[1] = $FF) then
      begin
        enc := teUtf16BE;
        bom := 2;
      end
      else if AEncoding = teUtf8Bom then
        enc := teUtf8;
    teUtf16LE:
      if (n >= 2) and (head[0] = $FF) and (head[1] = $FE) then bom := 2;
    teUtf16BE:
      if (n >= 2) and (head[0] = $FE) and (head[1] = $FF) then bom := 2;
  end;
  Dec(size, bom);
  AStream.Position := start + bom;
  text := nil;
  if enc = teAuto then
  begin
    // most files that are not UTF-8 show it in their first chunk: then the whole file is
    // never read into one buffer
    probe := nil;
    if size > ChunkSize then SetLength(probe, ChunkSize) else SetLength(probe, size);
    if Length(probe) > 0 then AStream.ReadBuffer(probe[0], Length(probe));
    AStream.Position := start + bom;
    if ValidUtf8(PByte(probe), Length(probe), size > Length(probe)) then enc := teUtf8
    else enc := teAnsi;
    probe := nil;
  end;
  if enc in [teUtf8, teUtf8Bom] then
  begin
    buf := nil;
    SetLength(buf, size);
    ReadInto(AStream, PByte(buf), size);
    // the load scan tells whether the rest is valid too, in the pass it makes anyway
    text := TTyRichText.CreateFromUtf8(buf);
    if (AEncoding = teAuto) and (enc = teUtf8) and (text.LoadedInvalidBytes > 0) then
    begin
      FreeAndNil(text);
      buf := nil;
      AStream.Position := start;
      enc := teAnsi;
    end;
  end;
  cp := 0;
  if text = nil then
    case enc of
      teUtf16LE, teUtf16BE:
        text := ConvertStream(AStream, size, nil, enc = teUtf16BE);
    else
      cp := TyRichAnsiCodePage(ACodePage);
      text := ConvertStream(AStream, size, TableFor(cp), False);
    end;
  // the document takes the text over, also when it refuses it
  TTextIOBuilder.Replace(ADoc, text, enc, cp, bom > 0);
end;

{ ---- writing ---- }

constructor TTextSaver.Create(AText: TTyRichText; AStream: TStream; AEnc: TTyTextEncoding;
  ATable: TCodePageTable);
begin
  inherited Create;
  FText := AText;
  FStream := AStream;
  FEnc := AEnc;
  FTable := ATable;
  FBuf := GetMem(SaveBufSize);
  FPrefix := -1;
end;

destructor TTextSaver.Destroy;
begin
  FreeMem(FBuf);
  inherited Destroy;
end;

procedure TTextSaver.Flush;
begin
  if FLen > 0 then FStream.WriteBuffer(FBuf^, FLen);
  FLen := 0;
end;

procedure TTextSaver.Room(AMore: Integer);
begin
  if FLen + AMore > SaveBufSize then Flush;
end;

procedure TTextSaver.PutByte(B: Byte);
begin
  Room(1);
  FBuf[FLen] := B;
  Inc(FLen);
end;

procedure TTextSaver.PutUnit(U: Cardinal);
begin
  Room(2);
  if FEnc = teUtf16BE then
  begin
    FBuf[FLen] := U shr 8;
    FBuf[FLen + 1] := Byte(U);
  end
  else
  begin
    FBuf[FLen] := Byte(U);
    FBuf[FLen + 1] := U shr 8;
  end;
  Inc(FLen, 2);
end;

{ A character or byte the target cannot hold. }
procedure TTextSaver.PutUnknown;
begin
  if FEnc = teAnsi then PutByte(Ord('?')) else PutUnit($FFFD);
end;

{$PUSH}{$Q-}{$R-}
{ One unit the fast loop of Put leaves alone: an escape, a sequence starting E0, ED or F0..F4,
  or a byte that is not UTF-8. }
procedure TTextSaver.PutOther(var P: PByte; E: PByte);
var
  b: Byte;
  n: Integer;
  code, r: Cardinal;
begin
  b := P^;
  if FPrefix >= 0 then
  begin
    // an escape cut by a piece boundary
    if b and $C0 = $80 then
    begin
      PutByte(((FPrefix and 3) shl 6) or (b and $3F));
      Inc(P);
    end
    else
      PutUnknown;
    FPrefix := -1;
    Exit;
  end;
  if (b >= $F8) and (b <= $FB) then
  begin
    if P + 1 = E then
      FPrefix := b
    else if P[1] and $C0 = $80 then
    begin
      PutByte(((b and 3) shl 6) or (P[1] and $3F));
      Inc(P);
    end
    else
      PutUnknown;
    Inc(P);
    Exit;
  end;
  n := DecodeUtf8(P, E - P, code);
  if n = 0 then
  begin
    PutUnknown;
    Inc(P);
    Exit;
  end;
  Inc(P, n);
  if FEnc = teAnsi then
  begin
    if code <= $FFFF then r := FTable.Rev[code] else r := 0;
    if r = 0 then PutByte(Ord('?'))
    else if r < $100 then PutByte(r)
    else
    begin
      Room(2);
      FBuf[FLen] := r shr 8;
      FBuf[FLen + 1] := Byte(r);
      Inc(FLen, 2);
    end;
  end
  else if code < $10000 then
    PutUnit(code)
  else
  begin
    PutUnit($D800 + ((code - $10000) shr 10));
    PutUnit($DC00 + ((code - $10000) and $3FF));
  end;
end;

procedure TTextSaver.Put(P: PByte; ACount: PtrInt);
var
  e, d, lim: PByte;
  rev: PWord;
  b: Byte;
  code, r: Cardinal;
  big: Boolean;
begin
  if ACount <= 0 then Exit;
  if FEnc in [teUtf8, teUtf8Bom] then
  begin
    // the stored bytes are the file's
    if ACount >= SaveBufSize then
    begin
      Flush;
      FStream.WriteBuffer(P^, ACount);
      Exit;
    end;
    Room(ACount);
    Move(P^, FBuf[FLen], ACount);
    Inc(FLen, ACount);
    Exit;
  end;
  e := P + ACount;
  if FTable <> nil then rev := PWord(FTable.Rev) else rev := nil;
  big := FEnc = teUtf16BE;
  while P < e do
  begin
    if FPrefix < 0 then
    begin
      // the characters text is made of, straight into the buffer: ASCII, two and three bytes
      d := FBuf + FLen;
      lim := FBuf + SaveBufSize - 8;
      while (P < e) and (d <= lim) do
      begin
        b := P^;
        if b < $80 then
        begin
          code := b;
          Inc(P);
        end
        else if (b >= $C2) and (b < $E0) and (e - P >= 2) and (P[1] and $C0 = $80) then
        begin
          code := (Cardinal(b and $1F) shl 6) or (P[1] and $3F);
          Inc(P, 2);
        end
        else if (b > $E0) and (b < $F0) and (b <> $ED) and (e - P >= 3) and
          (P[1] and $C0 = $80) and (P[2] and $C0 = $80) then
        begin
          code := (Cardinal(b and $0F) shl 12) or (Cardinal(P[1] and $3F) shl 6) or (P[2] and $3F);
          Inc(P, 3);
        end
        else
          Break;
        if rev <> nil then
        begin
          // ASCII is itself, NUL included (a Rev entry of 0 means "none")
          if code < $80 then
          begin
            d^ := code;
            Inc(d);
            Continue;
          end;
          r := rev[code];
          if r = 0 then
          begin
            d^ := Ord('?');
            Inc(d);
          end
          else if r < $100 then
          begin
            d^ := r;
            Inc(d);
          end
          else
          begin
            d[0] := r shr 8;
            d[1] := Byte(r);
            Inc(d, 2);
          end;
        end
        else if big then
        begin
          d[0] := code shr 8;
          d[1] := Byte(code);
          Inc(d, 2);
        end
        else
        begin
          d[0] := Byte(code);
          d[1] := code shr 8;
          Inc(d, 2);
        end;
      end;
      FLen := d - FBuf;
      if P >= e then Break;
      if d > lim then
      begin
        Flush;
        Continue;
      end;
    end;
    PutOther(P, e);
  end;
end;
{$POP}

procedure TTextSaver.Run(const ARun: TTyRichByteRun; var AContinue: Boolean);
begin
  if ARun.Bytes = nil then
  begin
    // a lazy paragraph: read it outside the walk
    FLazyChars := ARun.CharCount;
    AContinue := False;
    Exit;
  end;
  Put(ARun.Bytes, ARun.ByteCount);
  Inc(FPos, ARun.CharCount);
end;

procedure TTextSaver.Save;
var
  len: TTyRichPos;
  s: UTF8String;
begin
  len := FText.Length;
  FPos := 0;
  while FPos < len do
  begin
    FLazyChars := 0;
    FText.ForEachRun(FPos, len - FPos, @Run);
    if FLazyChars > 0 then
    begin
      s := FText.GetText(FPos, FLazyChars);
      Put(PByte(s), Length(s));
      Inc(FPos, FLazyChars);
    end;
  end;
  if FPrefix >= 0 then PutUnknown;
  FPrefix := -1;
  Flush;
end;

procedure TyRichSaveText(ADoc: TTyRichDocument; AStream: TStream);
const
  Utf8Bom: array[0..2] of Byte = ($EF, $BB, $BF);
  Utf16LEBom: array[0..1] of Byte = ($FF, $FE);
  Utf16BEBom: array[0..1] of Byte = ($FE, $FF);
var
  saver: TTextSaver;
  table: TCodePageTable;
  enc: TTyTextEncoding;
begin
  if (ADoc = nil) or (AStream = nil) then
    raise ETyRichTextIO.Create('TyRichSaveText needs a document and a stream');
  enc := ADoc.SourceEncoding;
  if enc = teAuto then enc := teUtf8;
  table := nil;
  if enc = teAnsi then table := TableFor(TyRichAnsiCodePage(ADoc.SourceCodePage));
  if ADoc.SourceHasBom then
    case enc of
      teUtf8, teUtf8Bom: AStream.WriteBuffer(Utf8Bom, 3);
      teUtf16LE: AStream.WriteBuffer(Utf16LEBom, 2);
      teUtf16BE: AStream.WriteBuffer(Utf16BEBom, 2);
    end;
  saver := TTextSaver.Create(ADoc.Text, AStream, enc, table);
  try
    saver.Save;
  finally
    saver.Free;
  end;
end;

procedure FreeTables;
var
  i: Integer;
begin
  if Tables = nil then Exit;
  for i := 0 to Tables.Count - 1 do TObject(Tables[i]).Free;
  FreeAndNil(Tables);
end;

finalization
  FreeTables;
end.
