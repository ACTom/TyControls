unit tyControls.RichEdit.RtfWrite;

// Writing TTyRichEdit's document (tyControls.RichEdit.Model) as RTF.
//
// A document that was read from an RTF file (tyControls.RichEdit.RtfRead) goes back as that
// file: the header's bytes, then every paragraph that is still the file's own - never parsed,
// or parsed and not changed - as the bytes it was read from, then the trailer's bytes. So a
// file opened and saved is the same file, and what the reader did not understand is still
// there. There is no shortcut for that case: it is what the one way of writing gives when no
// paragraph was changed.
//
// A paragraph that was changed is written from the model. RTF carries its state from one
// paragraph to the next (the font, the paragraph properties, \uc, a group left open), so the
// bytes that follow a rewritten paragraph only mean what they meant if the reader is in the
// state it was in when it first read them. Therefore:
// - what is rewritten is a stretch of paragraphs between two clean places of the file: a
//   paragraph's start where no table row is open (and no group that is a destination). A
//   changed paragraph in a table row takes its row along; they are written from the model
//   too;
// - before the stretch the groups the file left open there are closed; after it the reader
//   is put back: each of the groups that are open at that place of the file is opened again
//   with the properties it saved, and then \pard\plain and every property in effect there,
//   known and unknown (TyRtfStateWords), as the file itself had it - not a difference to
//   what was just written;
// - the header is only added to: a font or a colour the rewritten paragraphs need and the
//   file's tables lack goes in at the end of its table.
// The same holds where paragraphs were deleted: the bytes after the gap get their state back.
//
// A document with no file behind it is one stretch with a header of its own, in WordPad's
// writing: every character above 7F as \uN? under \uc1 (nothing written here is a byte
// above 7F), fonts in a font table with their \fcharset, \par after every paragraph.
//
// Saving reads the model; it changes nothing in the document (a paragraph it has to write
// from the model is parsed if it was not).

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
{$inline on}

interface

uses
  Classes, SysUtils, Graphics, LCLType, tyControls.RichEdit.Text, tyControls.RichEdit.Model,
  tyControls.RichEdit.RtfRead;

type
  ETyRichRtfWrite = class(ETyRichRtf);

  // Paragraphs written from the model: ParaCount of them from FirstPara (none where only a
  // deletion was closed), as the bytes [OutStart, OutStop) of the output - the words that
  // put the reader's state back after them included.
  TTyRtfWriteStretch = record
    FirstPara: Integer;
    ParaCount: Integer;
    OutStart: Int64;
    OutStop: Int64;
  end;

  // What a save did (tests and probes).
  TTyRtfWriteInfo = record
    HeaderStop: Int64;            // where the body starts in the output
    TrailerStart: Int64;          // where what follows the last paragraph starts
    Stretches: array of TTyRtfWriteStretch;
    RewrittenParas: Int64;
    VerbatimParas: Int64;         // copied from the file
  end;

// Writes ADoc to AStream as RTF. Raises ETyRichRtfWrite, and writes nothing, when ADoc is
// Incomplete (a cancelled load: the rest of the file is not in it) or still Loading (finish
// the load first: TTyRtfLoad.Step).
procedure TyRichSaveRtf(ADoc: TTyRichDocument; AStream: TStream); overload;
procedure TyRichSaveRtf(ADoc: TTyRichDocument; AStream: TStream; out AInfo: TTyRtfWriteInfo);
  overload;

implementation

uses
  tyControls.RichEdit.TextIO;

const
  OutBufSize = 64 * 1024;
  // How far back a numbered paragraph's place in its list is counted (its number is only
  // text for readers that do not number themselves).
  MaxListWalk = 10000;
  HexDigits: array[0..15] of Char = '0123456789abcdef';

type
  // How a paragraph's list is written: not at all, by the \ls its Extra holds (Word's list
  // table), by {\*\pn ...} around the fragments its Extra holds, or by one made here.
  TListMode = (lmNone, lmLs, lmPn, lmGen);

  TFontRec = record
    Name: string;        // as the model has it: UTF-8
    Charset: Integer;    // -1: the entry names none
    Num: Integer;
  end;

  TColorRec = record
    Value: TColor;
    Auto: Boolean;
  end;

  // A font name used with no charset: which table entry it gets is decided when every use
  // has been seen.
  TDefName = record
    Name: string;
    Kana, Hangul, Han: Boolean;   // in the name, or in text written in it
    Known: Boolean;               // the table has a font of this name: the text is not looked at
    Font: Integer;
  end;

  TCharInfo = record
    Seen: Boolean;
    Fmt: TTyCharFormat;
    Font: Integer;       // index into the fonts, -1 none, -2 by name (DefName)
    DefName: Integer;
    Color, Highlight: Integer;
    OneShot: Boolean;    // its Extra ends with \-, which holds for one character only
  end;
  PCharInfo = ^TCharInfo;

  TParaInfo = record
    Seen: Boolean;
    Fmt: TTyParaFormat;
    Mode: TListMode;
    Kinds: array of TTyRtfParaExtraKind;
    PnFont: Integer;                 // \pnfN among the fragments, -1 none
    PnBefore, PnAfter: RawByteString; // what {\pntxtb ...} and {\pntxta ...} hold
  end;
  PParaInfo = ^TParaInfo;

  TPlanItem = record
    Stretch: Boolean;
    First, Count: Integer;   // paragraphs
    Start, Stop: Int64;      // a block: its bytes; a stretch: the file position it begins at
                             // and the one the file goes on from (-1: the end of the body)
  end;

  TRtfWriter = class
  private
    FDoc: TTyRichDocument;
    FLoad: TTyRtfLoad;
    FStream: TStream;
    FPool: TTyFormatPool;
    FInfo: TTyRtfWriteInfo;
    FStretchN: Integer;
    // output
    FBuf: array of Byte;
    FBufLen: Integer;
    FWritten: Int64;
    FNeedDelim: Boolean;     // a control word of ours was written last: text needs a delimiter
    FRawOpen: Boolean;       // a fragment of the file ending in a control word was written last
    // the tables
    FTablesReady, FFrozen: Boolean;
    FFonts: array of TFontRec;
    FFontN, FOldFontN, FNextFontNum: Integer;
    FNoFontNum: Integer;     // a font number the table never defines: text with no font
    FColors: array of TColorRec;
    FColorN, FOldColorN: Integer;
    FDefNames: array of TDefName;
    FDefNameN: Integer;
    FChars: array of TCharInfo;
    FParas: array of TParaInfo;
    FSymbolNeeded: Boolean;
    FSymbol: Integer;
    // the plan
    FPlan: array of TPlanItem;
    FPlanN: Integer;
    FParaCount: Integer;
    FHeaderStop: Int64;
    FTrailer: TTyRtfRange;
    FLastOpen: Boolean;
    FInStretch: Boolean;
    FStretchFirst: Integer;
    FStretchX: Int64;
    FBlockFirst: Integer;
    FBlockStart, FFilePos: Int64;
    FCleanPos: Int64;
    FCleanResult: Boolean;
    // a stretch being written
    FCurChar: Integer;
    FCurSymbol: Boolean;     // the font in effect is of the Symbol charset
    FCurPara: Integer;
    FCurInCell: Boolean;
    FWroteRow: Boolean;
    FLastRowDef: RawByteString;
    FStartRowDef: RawByteString;   // the row definition in effect where the stretch began
    FNumPara, FNum: Integer;
    FNumList: TTyListFormat;
    // output
    procedure Flush;
    procedure Put(P: PByte; ACount: Int64);
    procedure PutB(B: Byte); inline;
    procedure PutS(const S: string);
    procedure PutRaw(const S: RawByteString);
    function OutPos: Int64;
    procedure Word(const AName: string);
    procedure WordN(const AName: string; AValue: Int64);
    procedure Sym(const S: string);
    procedure Lit(B: Byte);
    procedure Raw(const S: RawByteString);
    procedure RawText(const S: RawByteString);
    procedure NewLine;
    procedure Hex(B: Byte);
    // tables
    procedure EnsureTables;
    function FindFont(const AName: string; ACharset: Integer): Integer;
    function AddFont(const AName: string; ACharset: Integer): Integer;
    function DefNameIndex(const AName: string): Integer;
    function ColorIndex(AColor: TColor): Integer;
    function CharInfo(AId: Integer): PCharInfo;
    function ParaInfo(AId: Integer): PParaInfo;
    function FontOf(AId: Integer): Integer;
    function FontNumOf(AId: Integer): Integer;
    procedure NotePara(AIndex: Integer);
    procedure ScanText(AIndex: Integer; const ARuns: TTyRunArray);
    procedure FinishTables;
    procedure WriteFontEntry(const F: TFontRec; AAnsiCp: Integer);
    procedure WriteFonts(AFrom: Integer; AWhole: Boolean; AAnsiCp: Integer);
    procedure WriteColors(AFrom: Integer; AWhole: Boolean);
    procedure WriteHeaderOfFile;
    procedure WriteHeaderOfOurs;
    // the plan
    procedure AddItem(AStretch: Boolean; AFirst, ACount: Integer; AStart, AStop: Int64);
    function CleanAt(APos: Int64): Boolean;
    function RowStartsAt(AIndex: Integer; AStretchSideFirst: Boolean): Boolean;
    procedure OpenStretch(AIndex: Integer; AGap: Boolean);
    procedure CloseStretch(AIndex: Integer; AStop: Int64);
    procedure PlanPara(AIndex: Integer; AData: Pointer; ASrcOffset, ASrcBytes: Int64;
      var AContinue: Boolean);
    procedure NoteWalk(AIndex: Integer; AData: Pointer; ASrcOffset, ASrcBytes: Int64;
      var AContinue: Boolean);
    procedure PlanFile;
    // paragraphs from the model
    procedure WriteStretch(AFirst, ACount: Integer);
    procedure WriteRowDef(ARow: TTyRichRow);
    procedure WritePara(AIndex: Integer; APos, ALen: Int64; AInCell: Boolean);
    procedure WriteParaFormat(AIndex: Integer; AInfo: PParaInfo; AInCell: Boolean;
      AFirstFont: Integer);
    procedure WritePnWords(const AList: TTyListFormat);
    procedure WritePnText(AIndex: Integer; AInfo: PParaInfo; AFirstFont: Integer);
    function ListNumber(AIndex: Integer; const AList: TTyListFormat): Integer;
    procedure WriteCharFormat(AId: Integer);
    procedure WriteChar(ACode: Cardinal);
    procedure WriteUnit(AUnit: Cardinal);
    procedure WriteObject(AObj: TTyRichObject);
    procedure WritePicture(APic: TTyRichPicture);
    procedure LeaveGroupsAt(APos: Int64);
    procedure RestoreAt(APos: Int64; ANext: Integer);
    procedure BalanceTrailer;
    procedure AddStretchInfo(AFirst, ACount: Integer; AOutStart: Int64);
    procedure SaveFile;
    procedure SaveOurs;
  public
    constructor Create(ADoc: TTyRichDocument; AStream: TStream);
    procedure Run;
    property Info: TTyRtfWriteInfo read FInfo;
  end;

// ---- small helpers ----

function SameBytes(const A, B: RawByteString): Boolean;
begin
  Result := (Length(A) = Length(B)) and ((A = '') or CompareMem(@A[1], @B[1], Length(A)));
end;

function SameName(const A, B: string): Boolean;
begin
  Result := (Length(A) = Length(B)) and ((A = '') or CompareMem(@A[1], @B[1], Length(A)));
end;

// The bytes of S as a string of the model (a font name), with no conversion.
function AsModelString(const S: RawByteString): string;
begin
  Result := '';
  SetLength(Result, Length(S));
  if S <> '' then Move(S[1], Result[1], Length(S));
end;

function BytesOfRange(const ABytes: TBytes; const R: TTyRtfRange): RawByteString;
begin
  Result := '';
  if (R.Start < 0) or (R.Stop > Length(ABytes)) or (R.Stop <= R.Start) then Exit;
  SetLength(Result, R.Stop - R.Start);
  Move(ABytes[R.Start], Result[1], R.Stop - R.Start);
end;

// The character at P, of ALeft bytes: its code and how many bytes it is. A byte that starts
// no valid UTF-8 sequence is one character (as the text storage counts it) and reads U+FFFD.
function NextChar(P: PByte; ALeft: PtrInt; out ACode: Cardinal): Integer;
var
  b: Byte;
  c: Cardinal;
begin
  b := P^;
  if b < $80 then
  begin
    ACode := b;
    Exit(1);
  end;
  ACode := $FFFD;
  Result := 1;
  if (b >= $C2) and (b <= $DF) then
  begin
    if (ALeft >= 2) and (P[1] and $C0 = $80) then
    begin
      ACode := (Cardinal(b and $1F) shl 6) or (P[1] and $3F);
      Result := 2;
    end;
  end
  else if (b >= $E0) and (b <= $EF) then
  begin
    if (ALeft >= 3) and (P[1] and $C0 = $80) and (P[2] and $C0 = $80) then
    begin
      c := (Cardinal(b and $0F) shl 12) or (Cardinal(P[1] and $3F) shl 6) or (P[2] and $3F);
      if (c >= $800) and ((c < $D800) or (c > $DFFF)) then
      begin
        ACode := c;
        Result := 3;
      end;
    end;
  end
  else if (b >= $F0) and (b <= $F4) then
  begin
    if (ALeft >= 4) and (P[1] and $C0 = $80) and (P[2] and $C0 = $80) and
       (P[3] and $C0 = $80) then
    begin
      c := (Cardinal(b and $07) shl 18) or (Cardinal(P[1] and $3F) shl 12) or
        (Cardinal(P[2] and $3F) shl 6) or (P[3] and $3F);
      if (c >= $10000) and (c <= $10FFFF) then
      begin
        ACode := c;
        Result := 4;
      end;
    end;
  end;
end;

// What a character says about the font it is written in, when the font names no charset.
procedure Classify(ACode: Cardinal; var AKana, AHangul, AHan: Boolean);
begin
  case ACode of
    $3040..$30FF, $31F0..$31FF, $FF66..$FF9F:
      AKana := True;
    $1100..$11FF, $3130..$318F, $AC00..$D7AF:
      AHangul := True;
    $2E80..$2FDF, $3400..$4DBF, $4E00..$9FFF, $F900..$FAFF, $20000..$3FFFF:
      AHan := True;
  end;
end;

procedure ClassifyText(const S: string; var AKana, AHangul, AHan: Boolean);
var
  p, n: PtrInt;
  code: Cardinal;
begin
  p := 1;
  while p <= Length(S) do
  begin
    n := NextChar(@S[p], Length(S) - p + 1, code);
    Classify(code, AKana, AHangul, AHan);
    Inc(p, n);
  end;
end;

function SameList(const A, B: TTyListFormat): Boolean; inline;
begin
  Result := (A.Kind = B.Kind) and (A.Level = B.Level) and (A.StartAt = B.StartAt);
end;

function RomanNumber(AValue: Integer): string;
const
  Vals: array[0..12] of Integer = (1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1);
  Syms: array[0..12] of string = ('m', 'cm', 'd', 'cd', 'c', 'xc', 'l', 'xl', 'x', 'ix', 'v',
    'iv', 'i');
var
  i: Integer;
begin
  Result := '';
  if (AValue <= 0) or (AValue > 3999) then Exit(IntToStr(AValue));
  for i := 0 to High(Vals) do
    while AValue >= Vals[i] do
    begin
      Result := Result + Syms[i];
      Dec(AValue, Vals[i]);
    end;
end;

// a, b, ... z, aa, ab, ...
function AlphaNumber(AValue: Integer): string;
begin
  Result := '';
  if AValue <= 0 then Exit(IntToStr(AValue));
  while AValue > 0 do
  begin
    Dec(AValue);
    Result := Chr(Ord('a') + AValue mod 26) + Result;
    AValue := AValue div 26;
  end;
end;

function ListNumberText(AKind: TTyListKind; AValue: Integer): string;
begin
  case AKind of
    lkLowerAlpha: Result := AlphaNumber(AValue);
    lkUpperAlpha: Result := UpperCase(AlphaNumber(AValue));
    lkLowerRoman: Result := RomanNumber(AValue);
    lkUpperRoman: Result := UpperCase(RomanNumber(AValue));
  else
    Result := IntToStr(AValue);
  end;
end;

// A fragment that ends with a control word and no delimiter: text right after it would be
// read as part of the word.
function EndsInOpenWord(const S: RawByteString): Boolean;
var
  i, q, slashes: Integer;
begin
  Result := False;
  i := Length(S);
  if i < 2 then Exit;
  while (i >= 1) and (S[i] in ['0'..'9']) do Dec(i);
  if (i >= 1) and (S[i] = '-') and (i < Length(S)) then Dec(i);
  q := i;
  while (i >= 1) and (S[i] in ['a'..'z', 'A'..'Z']) do Dec(i);
  if (i = q) or (i < 1) or (S[i] <> '\') then Exit;
  // the backslash is one that starts a word, not an escaped backslash before text
  slashes := 0;
  while (i >= 1) and (S[i] = '\') do
  begin
    Inc(slashes);
    Dec(i);
  end;
  Result := Odd(slashes);
end;

// What a {\pntxta ...} or {\pntxtb ...} fragment holds.
function PnTextOf(const AFragment: RawByteString; const AWord: string): RawByteString;
var
  head: string;
  n: Integer;
begin
  Result := '';
  head := '{\' + AWord;
  n := Length(head);
  if (Length(AFragment) <= n) or not CompareMem(@AFragment[1], @head[1], n) or
     (AFragment[Length(AFragment)] <> '}') then
    Exit;
  Result := Copy(AFragment, n + 1, Length(AFragment) - n - 1);
  // the word's delimiter is not the text
  if (Result <> '') and (Result[1] = ' ') then Delete(Result, 1, 1);
  SetCodePage(Result, CP_NONE, False);
end;

function PlainColor(AColor: TColor): TColor;
begin
  // a system colour is written as what it is now
  if (Cardinal(AColor) and $FF000000) <> 0 then Result := ColorToRGB(AColor) and $FFFFFF
  else Result := AColor;
end;

// ---- TRtfWriter: output ----

constructor TRtfWriter.Create(ADoc: TTyRichDocument; AStream: TStream);
begin
  inherited Create;
  FDoc := ADoc;
  FStream := AStream;
  FPool := ADoc.Formats;
  FLoad := TyRichRtfLoadOf(ADoc);
  FSymbol := -1;
  FCleanPos := -1;
  SetLength(FBuf, OutBufSize);
end;

procedure TRtfWriter.Flush;
begin
  if FBufLen = 0 then Exit;
  FStream.WriteBuffer(FBuf[0], FBufLen);
  Inc(FWritten, FBufLen);
  FBufLen := 0;
end;

procedure TRtfWriter.Put(P: PByte; ACount: Int64);
const
  Chunk = 256 * 1024 * 1024;
var
  n: Int64;
begin
  if ACount <= 0 then Exit;
  if ACount >= OutBufSize then
  begin
    // a block of the file goes out as it is, not through the buffer
    Flush;
    while ACount > 0 do
    begin
      n := ACount;
      if n > Chunk then n := Chunk;
      FStream.WriteBuffer(P^, n);
      Inc(FWritten, n);
      Inc(P, n);
      Dec(ACount, n);
    end;
    Exit;
  end;
  if FBufLen + ACount > OutBufSize then Flush;
  Move(P^, FBuf[FBufLen], ACount);
  Inc(FBufLen, ACount);
end;

procedure TRtfWriter.PutB(B: Byte);
begin
  if FBufLen = OutBufSize then Flush;
  FBuf[FBufLen] := B;
  Inc(FBufLen);
end;

procedure TRtfWriter.PutS(const S: string);
begin
  if S <> '' then Put(PByte(PChar(S)), Length(S));
end;

procedure TRtfWriter.PutRaw(const S: RawByteString);
begin
  if S <> '' then Put(PByte(PAnsiChar(S)), Length(S));
end;

function TRtfWriter.OutPos: Int64;
begin
  Result := FWritten + FBufLen;
end;

procedure TRtfWriter.Word(const AName: string);
begin
  PutB(Ord('\'));
  PutS(AName);
  FNeedDelim := True;
  FRawOpen := False;
end;

procedure TRtfWriter.WordN(const AName: string; AValue: Int64);
begin
  Word(AName + IntToStr(AValue));
end;

// A brace, a control symbol, \'xx: needs no delimiter and leaves none open.
procedure TRtfWriter.Sym(const S: string);
begin
  PutS(S);
  FNeedDelim := False;
  FRawOpen := False;
end;

// One byte of text.
procedure TRtfWriter.Lit(B: Byte);
begin
  if FNeedDelim then
    PutB(Ord(' '))
  else if FRawOpen then
    // a space here would become part of the file's fragment when it is read again; an
    // empty group ends the word and is nothing
    PutS('{}');
  PutB(B);
  FNeedDelim := False;
  FRawOpen := False;
end;

// A fragment of the file, as it is.
procedure TRtfWriter.Raw(const S: RawByteString);
begin
  if S = '' then Exit;
  PutRaw(S);
  FNeedDelim := False;
  FRawOpen := EndsInOpenWord(S);
end;

// Bytes of RTF text taken from a fragment, after a word of ours.
procedure TRtfWriter.RawText(const S: RawByteString);
begin
  if S = '' then Exit;
  if FNeedDelim and not (S[1] in ['\', '{', '}']) then PutB(Ord(' '));
  PutRaw(S);
  FNeedDelim := False;
  FRawOpen := EndsInOpenWord(S);
end;

procedure TRtfWriter.NewLine;
begin
  PutB(13);
  PutB(10);
  FNeedDelim := False;
  FRawOpen := False;
end;

procedure TRtfWriter.Hex(B: Byte);
begin
  PutB(Ord(HexDigits[B shr 4]));
  PutB(Ord(HexDigits[B and 15]));
end;

// ---- the tables ----

procedure TRtfWriter.EnsureTables;
var
  i: Integer;
  scan: TTyRtfParser;
  f: TTyRtfFont;
  auto: Boolean;
begin
  if FTablesReady then Exit;
  FTablesReady := True;
  FNoFontNum := -1;
  if FLoad = nil then
  begin
    // \f0 is kept for the document's default font
    FNextFontNum := 1;
    Exit;
  end;
  scan := FLoad.Scan;
  FFontN := scan.FontCount;
  FOldFontN := FFontN;
  SetLength(FFonts, FFontN);
  for i := 0 to FFontN - 1 do
  begin
    f := scan.Font(i);
    FFonts[i].Name := AsModelString(f.Name);
    FFonts[i].Charset := f.Charset;
    FFonts[i].Num := f.Num;
    if f.Num >= FNextFontNum then FNextFontNum := f.Num + 1;
  end;
  // a number \deff names without a font of that number must stay without one
  if scan.DefaultFont >= FNextFontNum then FNextFontNum := scan.DefaultFont + 1;
  FColorN := scan.ColorCount;
  FOldColorN := FColorN;
  SetLength(FColors, FColorN);
  for i := 0 to FColorN - 1 do
  begin
    FColors[i].Value := PlainColor(scan.Color(i, auto));
    FColors[i].Auto := auto;
  end;
end;

function TRtfWriter.FindFont(const AName: string; ACharset: Integer): Integer;
var
  i: Integer;
begin
  for i := 0 to FFontN - 1 do
    if (FFonts[i].Charset = ACharset) and SameName(FFonts[i].Name, AName) then Exit(i);
  Result := -1;
end;

function TRtfWriter.AddFont(const AName: string; ACharset: Integer): Integer;
begin
  if FFontN = Length(FFonts) then SetLength(FFonts, FFontN * 2 + 8);
  FFonts[FFontN].Name := AName;
  FFonts[FFontN].Charset := ACharset;
  FFonts[FFontN].Num := FNextFontNum;
  Inc(FNextFontNum);
  Result := FFontN;
  Inc(FFontN);
end;

function TRtfWriter.DefNameIndex(const AName: string): Integer;
var
  i: Integer;
begin
  for i := 0 to FDefNameN - 1 do
    if SameName(FDefNames[i].Name, AName) then Exit(i);
  if FFrozen then Exit(-1);
  if FDefNameN = Length(FDefNames) then SetLength(FDefNames, FDefNameN * 2 + 4);
  Result := FDefNameN;
  Inc(FDefNameN);
  FDefNames[Result] := Default(TDefName);
  FDefNames[Result].Name := AName;
  FDefNames[Result].Font := -1;
  for i := 0 to FFontN - 1 do
    if SameName(FFonts[i].Name, AName) then FDefNames[Result].Known := True;
  with FDefNames[Result] do ClassifyText(AName, Kana, Hangul, Han);
end;

// The colour table's index for a colour; 0 for none (the default text colour, no highlight).
function TRtfWriter.ColorIndex(AColor: TColor): Integer;
var
  i: Integer;
  c: TColor;
begin
  if (AColor = clDefault) or (AColor = clNone) then Exit(0);
  c := PlainColor(AColor);
  for i := 1 to FColorN - 1 do
    if not FColors[i].Auto and (FColors[i].Value = c) then Exit(i);
  if FFrozen then Exit(0);
  if FColorN + 2 > Length(FColors) then SetLength(FColors, FColorN * 2 + 8);
  if FColorN = 0 then
  begin
    // entry 0 names no colour
    FColors[0].Value := 0;
    FColors[0].Auto := True;
    FColorN := 1;
  end;
  FColors[FColorN].Value := c;
  FColors[FColorN].Auto := False;
  Result := FColorN;
  Inc(FColorN);
end;

function TRtfWriter.CharInfo(AId: Integer): PCharInfo;
var
  f: TTyCharFormat;
  n, k: Integer;
begin
  if AId >= Length(FChars) then
  begin
    n := Length(FChars) * 2 + 16;
    if n <= AId then n := AId + 1;
    SetLength(FChars, n);
  end;
  Result := @FChars[AId];
  if Result^.Seen then Exit;
  EnsureTables;
  f := FPool.CharFormat(AId);
  Result^.Seen := True;
  Result^.Fmt := f;
  Result^.Font := -1;
  Result^.DefName := -1;
  Result^.Color := ColorIndex(f.Color);
  Result^.Highlight := ColorIndex(f.HighlightColor);
  if f.FontName <> '' then
    if f.Charset <> DEFAULT_CHARSET then
    begin
      k := FindFont(f.FontName, f.Charset);
      if (k < 0) and not FFrozen then k := AddFont(f.FontName, f.Charset);
      Result^.Font := k;
    end
    else
    begin
      Result^.DefName := DefNameIndex(f.FontName);
      if Result^.DefName >= 0 then Result^.Font := -2;
    end;
  n := f.Extra.Count;
  Result^.OneShot := (n > 0) and SameBytes(f.Extra.Item(n - 1), '\-');
end;

function TRtfWriter.ParaInfo(AId: Integer): PParaInfo;
var
  n, i, param, ls, ilvl: Integer;
  frag: RawByteString;
  hasPn, hasLs: Boolean;
  resolved: TTyListFormat;
begin
  if AId >= Length(FParas) then
  begin
    n := Length(FParas) * 2 + 16;
    if n <= AId then n := AId + 1;
    SetLength(FParas, n);
  end;
  Result := @FParas[AId];
  if Result^.Seen then Exit;
  Result^.Seen := True;
  Result^.Fmt := FPool.ParaFormat(AId);
  Result^.PnFont := -1;
  Result^.PnBefore := '';
  Result^.PnAfter := '';
  n := Result^.Fmt.Extra.Count;
  SetLength(Result^.Kinds, n);
  hasPn := False;
  hasLs := False;
  ls := 0;
  ilvl := 0;
  for i := 0 to n - 1 do
  begin
    frag := Result^.Fmt.Extra.Item(i);
    Result^.Kinds[i] := TyRtfParaExtraKind(frag, param);
    case Result^.Kinds[i] of
      pekLs:
        begin
          hasLs := True;
          ls := param;
        end;
      pekIlvl: ilvl := param;
      pekPn:
        begin
          hasPn := True;
          if TyRtfFragmentIsWord(frag, 'pnf') then Result^.PnFont := param
          else if PnTextOf(frag, 'pntxtb') <> '' then Result^.PnBefore := PnTextOf(frag, 'pntxtb')
          else if PnTextOf(frag, 'pntxta') <> '' then Result^.PnAfter := PnTextOf(frag, 'pntxta');
        end;
    end;
  end;
  Result^.Mode := lmNone;
  if hasLs and (ls > 0) and (FLoad <> nil) then
  begin
    // Word's list: still what the file's list table says, or changed since
    resolved := TyDefaultParaFormat.List;
    FLoad.Scan.ResolveListRef(ls, ilvl, resolved);
    if SameList(resolved, Result^.Fmt.List) then Result^.Mode := lmLs;
  end;
  if (Result^.Mode = lmNone) and (Result^.Fmt.List.Kind <> lkNone) then
    if hasPn then Result^.Mode := lmPn else Result^.Mode := lmGen;
end;

function TRtfWriter.FontOf(AId: Integer): Integer;
var
  ci: PCharInfo;
begin
  ci := CharInfo(AId);
  Result := ci^.Font;
  if Result = -2 then Result := FDefNames[ci^.DefName].Font;
end;

function TRtfWriter.FontNumOf(AId: Integer): Integer;
var
  k: Integer;
begin
  k := FontOf(AId);
  if k >= 0 then Result := FFonts[k].Num else Result := -1;
end;

// A paragraph that will be written from the model: the fonts and colours it needs.
procedure TRtfWriter.NotePara(AIndex: Integer);
var
  runs: TTyRunArray;
  j: Integer;
  ci: PCharInfo;
  pi: PParaInfo;
  look: Boolean;
begin
  EnsureTables;
  runs := FDoc.RunsOf(AIndex);
  look := False;
  for j := 0 to High(runs) do
  begin
    ci := CharInfo(runs[j].Format);
    if (ci^.DefName >= 0) and not FDefNames[ci^.DefName].Known and
       not FDefNames[ci^.DefName].Kana then
      look := True;
  end;
  if look then ScanText(AIndex, runs);
  pi := ParaInfo(FDoc.ParaFormatOf(AIndex));
  // a bullet made here is the Symbol font's
  if (pi^.Mode = lmGen) and (pi^.Fmt.List.Kind = lkBullet) then FSymbolNeeded := True;
end;

// What the text written in a font that names no charset says about it.
procedure TRtfWriter.ScanText(AIndex: Integer; const ARuns: TTyRunArray);
var
  text: UTF8String;
  p, n, len: PtrInt;
  ch: Int64;
  r, d: Integer;
  code: Cardinal;
begin
  text := FDoc.Text.GetText(FDoc.Text.ParaStart(AIndex), FDoc.Text.ParaLength(AIndex));
  len := Length(text);
  p := 1;
  ch := 0;
  r := 0;
  while p <= len do
  begin
    while (r < High(ARuns)) and (ARuns[r + 1].Start <= ch) do Inc(r);
    n := NextChar(@text[p], len - p + 1, code);
    d := CharInfo(ARuns[r].Format)^.DefName;
    if d >= 0 then
      with FDefNames[d] do Classify(code, Kana, Hangul, Han);
    Inc(p, n);
    Inc(ch);
  end;
end;

// Every use has been seen: the names without a charset get their entries.
procedure TRtfWriter.FinishTables;
var
  d, i, k, cs: Integer;
begin
  if not FTablesReady then Exit;
  for d := 0 to FDefNameN - 1 do
  begin
    k := -1;
    // an entry of that name that names no charset either; else the first of that name
    for i := 0 to FFontN - 1 do
      if SameName(FFonts[i].Name, FDefNames[d].Name) and
         ((FFonts[i].Charset < 0) or (FFonts[i].Charset = DEFAULT_CHARSET)) then
      begin
        k := i;
        Break;
      end;
    if k < 0 then
      for i := 0 to FFontN - 1 do
        if SameName(FFonts[i].Name, FDefNames[d].Name) then
        begin
          k := i;
          Break;
        end;
    if k < 0 then
    begin
      // a new font: East Asian by its name or by the text written in it, else ANSI
      if FDefNames[d].Kana then cs := 128
      else if FDefNames[d].Hangul then cs := 129
      else if FDefNames[d].Han then cs := 134
      else cs := 0;
      k := AddFont(FDefNames[d].Name, cs);
    end;
    FDefNames[d].Font := k;
  end;
  if FSymbolNeeded then
  begin
    FSymbol := FindFont('Symbol', 2);
    if FSymbol < 0 then FSymbol := AddFont('Symbol', 2);
  end;
  if FLoad = nil then
  begin
    // \deff0: the document's default font, when it has a name (with none, no \f0 is defined
    // and plain text stays in the reader's own font)
    k := FontOf(FDoc.DefaultCharFormatId);
    if k >= 0 then FFonts[k].Num := 0;
  end
  else
    // text the file gives no font (a number its table lacks) is written with a number that
    // stays undefined - the first one free: without \f it would take the file's default font
    FNoFontNum := FNextFontNum;
  FFrozen := True;
end;

// {\fN\fnil\fcharsetN name;} - the name in the code page of its charset, every byte above
// 7F as \'xx: the system's RichEdit does not read \uN in the font table.
procedure TRtfWriter.WriteFontEntry(const F: TFontRec; AAnsiCp: Integer);
var
  cp, v: Integer;
  table: Pointer;
  p, n: PtrInt;
  code: Cardinal;
begin
  Sym('{');
  WordN('f', F.Num);
  Word('fnil');
  if F.Charset >= 0 then WordN('fcharset', F.Charset);
  PutB(Ord(' '));
  cp := TyRtfCharsetCodePage(F.Charset, AAnsiCp);
  table := nil;
  if cp > 0 then table := TyRichCodePageTable(cp);
  p := 1;
  while p <= Length(F.Name) do
  begin
    n := NextChar(@F.Name[p], Length(F.Name) - p + 1, code);
    Inc(p, n);
    if code < $80 then
    begin
      if (code < $20) or (Byte(code) in [Ord('\'), Ord('{'), Ord('}'), Ord(';')]) then
      begin
        PutS('\''');
        Hex(code);
      end
      else
        PutB(code);
      Continue;
    end;
    v := 0;
    if (cp = 0) and (code >= $F000) and (code <= $F0FF) then v := code - $F000
    else if table <> nil then v := TyRichCodePageBytes(table, code);
    if v > 255 then
    begin
      PutS('\''');
      Hex(v shr 8);
      PutS('\''');
      Hex(v and 255);
    end
    else if v >= $80 then
    begin
      PutS('\''');
      Hex(v);
    end
    else
    begin
      // the code page has no bytes for it
      FNeedDelim := False;
      WriteChar(code);
    end;
  end;
  Sym(';}');
end;

procedure TRtfWriter.WriteFonts(AFrom: Integer; AWhole: Boolean; AAnsiCp: Integer);
var
  order: array of Integer;
  i, j, t: Integer;
begin
  if AWhole then
  begin
    Sym('{\fonttbl');
    if (FLoad <> nil) and (FLoad.Scan.DefaultFont < 0) then
    begin
      // a file with no font table and no \deff: its text has no font, and a reader takes
      // the first font of a table for such text - so the first is one with no name
      Sym('{');
      WordN('f', FNoFontNum);
      Word('fnil');
      Sym(' ;}');
    end;
  end;
  // in the order of their numbers
  order := nil;
  SetLength(order, FFontN - AFrom);
  for i := 0 to High(order) do order[i] := AFrom + i;
  for i := 1 to High(order) do
  begin
    t := order[i];
    j := i - 1;
    while (j >= 0) and (FFonts[order[j]].Num > FFonts[t].Num) do
    begin
      order[j + 1] := order[j];
      Dec(j);
    end;
    order[j + 1] := t;
  end;
  for i := 0 to High(order) do WriteFontEntry(FFonts[order[i]], AAnsiCp);
  if AWhole then Sym('}');
end;

procedure TRtfWriter.WriteColors(AFrom: Integer; AWhole: Boolean);
var
  i: Integer;
begin
  if AWhole then Sym('{\colortbl ');
  for i := AFrom to FColorN - 1 do
  begin
    if not FColors[i].Auto then
    begin
      WordN('red', Red(FColors[i].Value));
      WordN('green', Green(FColors[i].Value));
      WordN('blue', Blue(FColors[i].Value));
    end;
    Sym(';');
  end;
  if AWhole then Sym('}');
end;

// The file's header with the new fonts and colours at the end of their tables (a table the
// file lacks is added: the colour table after the font table, the font table at the end of
// the header). Every other byte is the file's.
procedure TRtfWriter.WriteHeaderOfFile;
var
  bytes: TBytes;
  p, fAt, cAt, fClose, cClose, q: Int64;
  ansi: Integer;

  procedure UpTo(APos: Int64);
  begin
    if APos > p then Put(@bytes[p], APos - p);
    p := APos;
  end;

  procedure Fonts;
  begin
    UpTo(fAt);
    WriteFonts(FOldFontN, fClose < 0, ansi);
  end;

  procedure Colors;
  begin
    UpTo(cAt);
    if (cClose >= 0) and (FOldColorN > 0) then
    begin
      // the table's last entry may have been ended by the brace alone
      q := cClose - 1;
      while (q > 0) and (bytes[q] in [10, 13, 32]) do Dec(q);
      if bytes[q] <> Ord(';') then Sym(';');
    end;
    WriteColors(FOldColorN, cClose < 0);
  end;

begin
  bytes := FLoad.Bytes;
  p := 0;
  fAt := -1;
  cAt := -1;
  fClose := -1;
  cClose := -1;
  ansi := 1252;
  if FTablesReady then
  begin
    fClose := FLoad.Scan.FontTableClose;
    cClose := FLoad.Scan.ColorTableClose;
    ansi := FLoad.Scan.AnsiCodePage;
    if FFontN > FOldFontN then
      if fClose >= 0 then fAt := fClose else fAt := FHeaderStop;
    if FColorN > FOldColorN then
      if cClose >= 0 then cAt := cClose
      else if fClose >= 0 then cAt := fClose + 1
      else cAt := FHeaderStop;
  end;
  if (fAt >= 0) and ((cAt < 0) or (fAt <= cAt)) then
  begin
    Fonts;
    if cAt >= 0 then Colors;
  end
  else
  begin
    if cAt >= 0 then Colors;
    if fAt >= 0 then Fonts;
  end;
  UpTo(FHeaderStop);
  FNeedDelim := False;
  FRawOpen := False;
end;

// {\rtf1\ansi\ansicpgN\deff0\nouicompat{\fonttbl ...}{\colortbl ;...}\viewkind4\uc1
procedure TRtfWriter.WriteHeaderOfOurs;
var
  i, ansi: Integer;
begin
  // the code page of the first double-byte charset among the fonts, Chinese first
  ansi := 0;
  for i := 0 to FFontN - 1 do
    if FFonts[i].Charset = 134 then ansi := 936;
  if ansi = 0 then
    for i := 0 to FFontN - 1 do
    begin
      case FFonts[i].Charset of
        128: ansi := 932;
        129: ansi := 949;
        136: ansi := 950;
      end;
      if ansi <> 0 then Break;
    end;
  if ansi = 0 then ansi := 1252;
  Sym('{');
  Word('rtf1');
  Word('ansi');
  WordN('ansicpg', ansi);
  Word('deff0');
  Word('nouicompat');
  if FFontN > 0 then WriteFonts(0, True, ansi);
  NewLine;
  if FColorN > 0 then
  begin
    WriteColors(0, True);
    NewLine;
  end;
  if FDoc.PaperWidth <> 12240 then WordN('paperw', FDoc.PaperWidth);
  if FDoc.PaperHeight <> 15840 then WordN('paperh', FDoc.PaperHeight);
  if FDoc.MarginLeft <> 1800 then WordN('margl', FDoc.MarginLeft);
  if FDoc.MarginRight <> 1800 then WordN('margr', FDoc.MarginRight);
  Word('viewkind4');
  Word('uc1');
  PutB(Ord(' '));
  NewLine;
end;

// ---- the plan ----

procedure TRtfWriter.AddItem(AStretch: Boolean; AFirst, ACount: Integer; AStart, AStop: Int64);
begin
  if FPlanN = Length(FPlan) then SetLength(FPlan, FPlanN * 2 + 4);
  FPlan[FPlanN].Stretch := AStretch;
  FPlan[FPlanN].First := AFirst;
  FPlan[FPlanN].Count := ACount;
  FPlan[FPlanN].Start := AStart;
  FPlan[FPlanN].Stop := AStop;
  Inc(FPlanN);
end;

// A place of the file where the output can leave the file's bytes or come back to them: a
// paragraph's start with no table row open, where every open group is an ordinary one (it
// can be closed and opened again with the properties it saved).
function TRtfWriter.CleanAt(APos: Int64): Boolean;
var
  st: TTyRtfState;
  k: Integer;
begin
  if APos = FCleanPos then Exit(FCleanResult);
  Result := FLoad.StateAt(APos, st) and (st.Core.Depth >= 1) and
    (st.Core.Depth <= Length(st.Stack)) and (st.Core.Overflow = 0) and
    (st.Core.CellIdx = 0) and (st.Core.RowMax = 0) and (st.Core.Props.Dest = rdNormal) and
    not st.Core.Props.DestOwner and not st.Core.DocClosed and (st.Core.UcSkip = 0) and
    (st.Core.PendingLead < 0) and (st.Core.PendingHigh = 0);
  if Result then
    for k := 1 to st.Core.Depth - 1 do
      if (st.Stack[k].Dest <> rdNormal) or st.Stack[k].DestOwner then Result := False;
  FCleanPos := APos;
  FCleanResult := Result;
end;

// Paragraph AIndex does not go on the model's table row of the paragraph before it (a row
// is written whole). Asks the paragraph on the stretch's side first: it is parsed anyway,
// and when it is in no table the other one need not be.
function TRtfWriter.RowStartsAt(AIndex: Integer; AStretchSideFirst: Boolean): Boolean;
var
  a, b: TTyRichCell;
begin
  if (AIndex <= 0) or (AIndex >= FParaCount) then Exit(True);
  if AStretchSideFirst then
  begin
    a := FDoc.CellAt(AIndex - 1);
    if a = nil then Exit(True);
    b := FDoc.CellAt(AIndex);
  end
  else
  begin
    b := FDoc.CellAt(AIndex);
    if b = nil then Exit(True);
    a := FDoc.CellAt(AIndex - 1);
  end;
  Result := (a = nil) or (b = nil) or (a.Row <> b.Row);
end;

// The output cannot go on as the file does before paragraph AIndex: a stretch starts, at the
// last clean place at or before it (the paragraphs between are written from the model too).
// AGap: paragraph AIndex itself is the file's own (bytes of the file are missing before it),
// or there is none (the end).
procedure TRtfWriter.OpenStretch(AIndex: Integer; AGap: Boolean);
var
  a, k: Integer;
  x, s, n: Int64;
begin
  a := AIndex;
  x := FFilePos;
  while a > FBlockFirst do
  begin
    if CleanAt(x) and (((a = AIndex) and AGap) or RowStartsAt(a, False)) then Break;
    Dec(a);
    FDoc.Text.ParaLazySource(a, s, n);
    x := s;
  end;
  // (the block's own start is clean: the body's start, or where a stretch ended)
  if a = FBlockFirst then x := FBlockStart;
  if x > FBlockStart then AddItem(False, FBlockFirst, a - FBlockFirst, FBlockStart, x);
  FInStretch := True;
  FStretchFirst := a;
  FStretchX := x;
  for k := a to AIndex - 1 do NotePara(k);
end;

procedure TRtfWriter.CloseStretch(AIndex: Integer; AStop: Int64);
begin
  AddItem(True, FStretchFirst, AIndex - FStretchFirst, FStretchX, AStop);
  FInStretch := False;
end;

procedure TRtfWriter.PlanPara(AIndex: Integer; AData: Pointer; ASrcOffset, ASrcBytes: Int64;
  var AContinue: Boolean);
var
  own: Boolean;
begin
  // the file's own: its text is the unedited lazy paragraph and its formats are the file's.
  // The file's last paragraph, when it has no terminator, can only be copied as the last.
  own := (ASrcOffset >= FHeaderStop) and (ASrcOffset + ASrcBytes <= FTrailer.Start) and
    FLoad.OwnsValue(ASrcOffset, AData) and
    not (FLastOpen and (ASrcOffset + ASrcBytes = FTrailer.Start) and (AIndex < FParaCount - 1));
  if not FInStretch then
  begin
    if own and (ASrcOffset = FFilePos) then
    begin
      FFilePos := ASrcOffset + ASrcBytes;
      Exit;
    end;
    OpenStretch(AIndex, own);
  end;
  // the stretch ends before a paragraph of the file that starts at a clean place
  if own and CleanAt(ASrcOffset) and
     ((FStretchFirst = AIndex) or RowStartsAt(AIndex, True)) then
  begin
    CloseStretch(AIndex, ASrcOffset);
    FBlockFirst := AIndex;
    FBlockStart := ASrcOffset;
    FFilePos := ASrcOffset + ASrcBytes;
  end
  else
    NotePara(AIndex);
end;

procedure TRtfWriter.PlanFile;
begin
  FHeaderStop := FLoad.Header.Stop;
  FTrailer := FLoad.Trailer;
  FLastOpen := FLoad.LastParaOpen;
  FBlockFirst := 0;
  FBlockStart := FHeaderStop;
  FFilePos := FHeaderStop;
  FDoc.Text.WalkParas(0, @PlanPara);
  if not FInStretch and (FFilePos <> FTrailer.Start) then
    // the file's last paragraphs are gone
    OpenStretch(FParaCount, True);
  if FInStretch then
    CloseStretch(FParaCount, -1)
  else if FFilePos > FBlockStart then
    AddItem(False, FBlockFirst, FParaCount - FBlockFirst, FBlockStart, FFilePos);
  FinishTables;
end;

procedure TRtfWriter.NoteWalk(AIndex: Integer; AData: Pointer; ASrcOffset, ASrcBytes: Int64;
  var AContinue: Boolean);
begin
  // (a paragraph with no value is plain: the default formats, noted once)
  if AData <> nil then NotePara(AIndex);
end;

// ---- paragraphs from the model ----

procedure TRtfWriter.WriteStretch(AFirst, ACount: Integer);
var
  i, stop: Integer;
  pos, len: Int64;
  cell, next: TTyRichCell;
  prevRow: TTyRichRow;
begin
  FCurChar := -1;
  FCurSymbol := False;
  FCurPara := -1;
  FCurInCell := False;
  FWroteRow := False;
  FNumPara := -2;
  if ACount = 0 then Exit;
  // whatever \uc the file left in effect here: ours is one fallback character
  if FLoad <> nil then Word('uc1');
  stop := AFirst + ACount;
  pos := FDoc.Text.ParaStart(AFirst);
  cell := FDoc.CellAt(AFirst);
  // (the stretch starts and ends between rows: the plan saw to that)
  prevRow := nil;
  for i := AFirst to stop - 1 do
  begin
    if i + 1 < stop then next := FDoc.CellAt(i + 1) else next := nil;
    if (cell <> nil) and (cell.Row <> prevRow) then WriteRowDef(cell.Row);
    len := FDoc.Text.ParaLength(i);
    WritePara(i, pos, len, cell <> nil);
    if (cell = nil) or (next = cell) then
    begin
      Word('par');
      NewLine;
    end
    else
    begin
      Word('cell');
      if (next = nil) or (next.Row <> cell.Row) then
      begin
        Word('row');
        NewLine;
        // what follows a row starts from \pard
        FCurPara := -1;
      end;
    end;
    if cell <> nil then prevRow := cell.Row else prevRow := nil;
    Inc(pos, len + 1);
    cell := next;
  end;
end;

// \trowd and the row's own words as they were read; a row made here: \trgaph108 and its
// cells' right edges.
procedure TRtfWriter.WriteRowDef(ARow: TTyRichRow);
var
  def: RawByteString;
  s: string;
  i, n, edge: Integer;
begin
  def := ARow.RawFormat;
  if def = '' then
  begin
    s := '\trowd\trgaph108';
    edge := 0;
    n := ARow.CellCount;
    for i := 0 to n - 1 do
    begin
      if i < ARow.BoundaryCount then edge := ARow.Boundaries[i]
      else if (ARow.BoundaryCount = 0) and (i < ARow.Table.ColBoundaryCount) then
        edge := ARow.Table.ColBoundaries[i]
      else
        Inc(edge, 1440);
      s := s + '\cellx' + IntToStr(edge);
    end;
    def := s;
    SetCodePage(def, CP_NONE, False);
  end
  else if (Length(def) < 6) or not CompareMem(@def[1], PChar('\trowd'), 6) then
  begin
    PutS('\trowd');
  end;
  Raw(def);
  FLastRowDef := def;
  FWroteRow := True;
  // RichEdit starts every row's paragraphs from \pard\intbl
  FCurPara := -1;
end;

procedure TRtfWriter.WritePara(AIndex: Integer; APos, ALen: Int64; AInCell: Boolean);
var
  pf: TTyParaFormatId;
  runs: TTyRunArray;
  pi: PParaInfo;
  text: UTF8String;
  p, n, len: PtrInt;
  ch, runEnd: Int64;
  r, firstFont: Integer;
  code: Cardinal;
begin
  pf := FDoc.ParaFormatOf(AIndex);
  runs := FDoc.RunsOf(AIndex);
  pi := ParaInfo(pf);
  firstFont := -1;
  if Length(runs) > 0 then firstFont := FontNumOf(runs[0].Format);
  if (pf <> FCurPara) or (AInCell <> FCurInCell) then
  begin
    WriteParaFormat(AIndex, pi, AInCell, firstFont);
    FCurPara := pf;
    FCurInCell := AInCell;
  end
  else if (pi^.Mode in [lmPn, lmGen]) and (pi^.Fmt.List.Kind <> lkNone) then
    // the same list goes on: only the item's own text
    WritePnText(AIndex, pi, firstFont);
  if ALen > 0 then text := FDoc.Text.GetText(APos, ALen) else text := '';
  len := Length(text);
  p := 1;
  ch := 0;
  for r := 0 to High(runs) do
  begin
    if r < High(runs) then runEnd := runs[r + 1].Start else runEnd := ALen;
    if runs[r].Format <> FCurChar then WriteCharFormat(runs[r].Format);
    if runs[r].Obj <> nil then
    begin
      WriteObject(runs[r].Obj);
      // its one character
      if p <= len then
      begin
        Inc(p, NextChar(@text[p], len - p + 1, code));
        Inc(ch);
      end;
      Continue;
    end;
    while (ch < runEnd) and (p <= len) do
    begin
      n := NextChar(@text[p], len - p + 1, code);
      WriteChar(code);
      Inc(p, n);
      Inc(ch);
    end;
  end;
end;

// What {\*\pn ...} sets from the model's list.
procedure TRtfWriter.WritePnWords(const AList: TTyListFormat);
begin
  if AList.Kind = lkNone then Exit;
  if AList.Kind = lkBullet then
    Word('pnlvlblt')
  else
  begin
    if AList.Level > 0 then WordN('pnlvl', AList.Level + 1) else Word('pnlvlbody');
    case AList.Kind of
      lkDecimal: Word('pndec');
      lkLowerAlpha: Word('pnlcltr');
      lkUpperAlpha: Word('pnucltr');
      lkLowerRoman: Word('pnlcrm');
      lkUpperRoman: Word('pnucrm');
    end;
  end;
  if (AList.StartAt <> 0) or (AList.Kind <> lkBullet) then WordN('pnstart', AList.StartAt);
end;

// The paragraph's place in its list: its number counts the paragraphs of the same list
// right before it.
function TRtfWriter.ListNumber(AIndex: Integer; const AList: TTyListFormat): Integer;
var
  k, steps: Integer;
begin
  if (FNumPara = AIndex - 1) and SameList(FNumList, AList) then
    Result := FNum + 1
  else
  begin
    Result := AList.StartAt;
    if Result <= 0 then Result := 1;
    k := AIndex - 1;
    steps := 0;
    while (k >= 0) and (steps < MaxListWalk) and
      SameList(ParaInfo(FDoc.ParaFormatOf(k))^.Fmt.List, AList) do
    begin
      Inc(Result);
      Dec(k);
      Inc(steps);
    end;
  end;
  FNumPara := AIndex;
  FNumList := AList;
  FNum := Result;
end;

// {\pntext\f1\'B7\tab} or {\pntext\f0 1.\tab}: the bullet or number as text, for readers
// that do not make it themselves.
procedure TRtfWriter.WritePnText(AIndex: Integer; AInfo: PParaInfo; AFirstFont: Integer);
var
  font, i: Integer;
  s: string;
begin
  Sym('{');
  Word('pntext');
  if AInfo^.Fmt.List.Kind = lkBullet then
  begin
    if AInfo^.Mode = lmGen then
    begin
      if FSymbol >= 0 then WordN('f', FFonts[FSymbol].Num);
      Sym('\''B7');
    end
    else
    begin
      if AInfo^.PnFont >= 0 then WordN('f', AInfo^.PnFont);
      RawText(AInfo^.PnBefore);
    end;
  end
  else
  begin
    if AInfo^.Mode = lmGen then font := AFirstFont else font := AInfo^.PnFont;
    if font >= 0 then WordN('f', font);
    if AInfo^.Mode = lmPn then RawText(AInfo^.PnBefore);
    s := ListNumberText(AInfo^.Fmt.List.Kind, ListNumber(AIndex, AInfo^.Fmt.List));
    for i := 1 to Length(s) do Lit(Ord(s[i]));
    if AInfo^.Mode = lmGen then Lit(Ord('.')) else RawText(AInfo^.PnAfter);
  end;
  Word('tab');
  Sym('}');
end;

// \pard and everything of the paragraph format: the list, the fragments of Extra where the
// reader finds them again, then the properties the model has (after the fragments, so that
// the model's value is the one that holds).
procedure TRtfWriter.WriteParaFormat(AIndex: Integer; AInfo: PParaInfo; AInCell: Boolean;
  AFirstFont: Integer);
const
  TabAlignWord: array[TTyTabAlign] of string = ('', 'tqc', 'tqr', 'tqdec');
  TabLeaderWord: array[TTyTabLeader] of string = ('', 'tldot', 'tlhyph', 'tlul', 'tlth', 'tleq');
var
  i: Integer;
  inPn, pnDone: Boolean;
  list: TTyListFormat;
begin
  Word('pard');
  if AInCell then Word('intbl');
  list := AInfo^.Fmt.List;
  if (AInfo^.Mode in [lmPn, lmGen]) and (list.Kind <> lkNone) then
    WritePnText(AIndex, AInfo, AFirstFont);
  pnDone := False;
  if AInfo^.Mode = lmGen then
  begin
    // as RichEdit writes a list: {\*\pn\pnlvlblt\pnf1\pnindent0{\pntxtb\'B7}} and
    // {\*\pn\pnlvlbody\pnf0\pnindent0\pnstart1\pndec{\pntxta.}}
    Sym('{\*');
    Word('pn');
    if list.Kind = lkBullet then
    begin
      Word('pnlvlblt');
      if FSymbol >= 0 then WordN('pnf', FFonts[FSymbol].Num);
      Word('pnindent0');
      if list.StartAt <> 0 then WordN('pnstart', list.StartAt);
      Sym('{\pntxtb\''B7}');
    end
    else
    begin
      if list.Level > 0 then WordN('pnlvl', list.Level + 1) else Word('pnlvlbody');
      if AFirstFont >= 0 then WordN('pnf', AFirstFont);
      Word('pnindent0');
      WordN('pnstart', list.StartAt);
      case list.Kind of
        lkDecimal: Word('pndec');
        lkLowerAlpha: Word('pnlcltr');
        lkUpperAlpha: Word('pnucltr');
        lkLowerRoman: Word('pnlcrm');
        lkUpperRoman: Word('pnucrm');
      end;
      Sym('{\pntxta.}');
    end;
    Sym('}');
    pnDone := True;
  end;
  inPn := False;
  for i := 0 to AInfo^.Fmt.Extra.Count - 1 do
  begin
    // \ls and \ilvl name a list of the file's table: only while that is still the list
    if (AInfo^.Kinds[i] in [pekLs, pekIlvl]) and (AInfo^.Mode <> lmLs) then Continue;
    if AInfo^.Kinds[i] = pekPn then
    begin
      if not inPn then
      begin
        Sym('{\*');
        Word('pn');
        if not pnDone and (AInfo^.Mode = lmPn) then WritePnWords(list);
        pnDone := True;
        inPn := True;
      end;
    end
    else if inPn then
    begin
      Sym('}');
      inPn := False;
    end;
    Raw(AInfo^.Fmt.Extra.Item(i));
  end;
  if inPn then Sym('}');
  with AInfo^.Fmt do
  begin
    case Align of
      paraCenter: Word('qc');
      paraRight: Word('qr');
      paraJustify: Word('qj');
    end;
    if FirstIndent <> 0 then WordN('fi', FirstIndent);
    if LeftIndent <> 0 then WordN('li', LeftIndent);
    if RightIndent <> 0 then WordN('ri', RightIndent);
    if SpaceBefore <> 0 then WordN('sb', SpaceBefore);
    if SpaceAfter <> 0 then WordN('sa', SpaceAfter);
    case LineSpacing of
      ls115: Word('sl276\slmult1');
      ls15: Word('sl360\slmult1');
      lsDouble: Word('sl480\slmult1');
      lsExact:
        if LineSpacingValue > 0 then
        begin
          WordN('sl', -LineSpacingValue);
          Word('slmult0');
        end;
      lsAtLeast:
        if LineSpacingValue > 0 then
        begin
          WordN('sl', LineSpacingValue);
          Word('slmult0');
        end;
    end;
    for i := 0 to High(Tabs) do
    begin
      if Tabs[i].Align <> ttaLeft then Word(TabAlignWord[Tabs[i].Align]);
      if Tabs[i].Leader <> ttlNone then Word(TabLeaderWord[Tabs[i].Leader]);
      WordN('tx', Tabs[i].Position);
    end;
    if RtlPar then Word('rtlpar');
  end;
end;

// \plain and everything of the character format: the fragments of Extra first (text never
// follows one directly, so none gains a delimiter it did not have), then the font, the size
// and the rest.
procedure TRtfWriter.WriteCharFormat(AId: Integer);
var
  ci: PCharInfo;
  i, font: Integer;
begin
  font := FontOf(AId);
  ci := CharInfo(AId);
  Word('plain');
  for i := 0 to ci^.Fmt.Extra.Count - 1 do Raw(ci^.Fmt.Extra.Item(i));
  if font >= 0 then WordN('f', FFonts[font].Num)
  else if FNoFontNum >= 0 then WordN('f', FNoFontNum);
  FCurSymbol := (font >= 0) and (FFonts[font].Charset = SYMBOL_CHARSET);
  if ci^.Fmt.SizeHalfPt > 0 then WordN('fs', ci^.Fmt.SizeHalfPt);
  if fsBold in ci^.Fmt.Style then Word('b');
  if fsItalic in ci^.Fmt.Style then Word('i');
  if fsUnderline in ci^.Fmt.Style then Word('ul');
  if ci^.Fmt.Strike or (fsStrikeOut in ci^.Fmt.Style) then Word('strike');
  case ci^.Fmt.VertAlign of
    vaSuper: Word('super');
    vaSub: Word('sub');
  end;
  if ci^.Color > 0 then WordN('cf', ci^.Color);
  if ci^.Highlight > 0 then WordN('highlight', ci^.Highlight);
  // \- holds for the next character only: such a format is written again every time
  if ci^.OneShot then FCurChar := -1 else FCurChar := AId;
end;

procedure TRtfWriter.WriteUnit(AUnit: Cardinal);
var
  n: Integer;
begin
  n := AUnit;
  if n > 32767 then Dec(n, 65536);
  PutS('\u' + IntToStr(n) + '?');
  FNeedDelim := False;
  FRawOpen := False;
end;

procedure TRtfWriter.WriteChar(ACode: Cardinal);
begin
  // in a Symbol font a byte is not its ASCII character but the font's own (a reader gives
  // it U+F000 + the byte): the character itself can only be said by its number
  if FCurSymbol and (ACode > $20) and (ACode < $80) then
  begin
    WriteUnit(ACode);
    Exit;
  end;
  case ACode of
    9: Word('tab');
    $0B: Word('line');
    Ord('\'): Sym('\\');
    Ord('{'): Sym('\{');
    Ord('}'): Sym('\}');
    $20..$5B, $5D..$7A, $7C, $7E: Lit(ACode);
    $A0: Sym('\~');
    $2011: Sym('\_');
  else
    if ACode > $FFFF then
    begin
      WriteUnit($D800 + ((ACode - $10000) shr 10));
      WriteUnit($DC00 + ((ACode - $10000) and $3FF));
    end
    else
      WriteUnit(ACode);
  end;
end;

procedure TRtfWriter.WritePicture(APic: TTyRichPicture);
var
  i: Integer;
begin
  Sym('{');
  Word('pict');
  case APic.PictureFormat of
    rpfPng: Word('pngblip');
    rpfJpeg: Word('jpegblip');
    rpfDib: Word('dibitmap0');
    rpfBmp: Word('wbitmap0');
    rpfWmf: Word('wmetafile8');
    rpfEmf: Word('emfblip');
  end;
  if APic.PictureFormat in [rpfWmf, rpfEmf] then
  begin
    // a metafile's own size, in hundredths of a millimetre
    WordN('picw', Int64(APic.WidthTwips) * 2540 div 1440);
    WordN('pich', Int64(APic.HeightTwips) * 2540 div 1440);
  end;
  if APic.WidthTwips > 0 then WordN('picwgoal', APic.WidthTwips);
  if APic.HeightTwips > 0 then WordN('pichgoal', APic.HeightTwips);
  PutB(Ord(' '));
  for i := 0 to High(APic.Data) do
  begin
    if (i > 0) and (i mod 64 = 0) then
    begin
      PutB(13);
      PutB(10);
    end;
    Hex(APic.Data[i]);
  end;
  Sym('}');
end;

procedure TRtfWriter.WriteObject(AObj: TTyRichObject);
begin
  if AObj is TTyRichOpaque then
    Raw(TTyRichOpaque(AObj).Bytes)
  else if AObj is TTyRichPicture then
  begin
    if TTyRichPicture(AObj).RawRtf <> '' then Raw(TTyRichPicture(AObj).RawRtf)
    else WritePicture(TTyRichPicture(AObj));
  end
  else
    // an object of a kind this writer does not know: its character stays
    WriteUnit($FFFC);
end;

// ---- going on with the file ----

// Before a stretch, at byte APos of the file: the groups the file's paragraphs before it left
// open are closed (the file closes them later, in bytes that are not written or come after
// RestoreAt has opened them again), so the stretch is written with only the document's group
// open.
procedure TRtfWriter.LeaveGroupsAt(APos: Int64);
var
  st: TTyRtfState;
  d: Integer;
begin
  FStartRowDef := '';
  if not FLoad.StateAt(APos, st) then Exit;
  for d := 2 to st.Core.Depth do PutB(Ord('}'));
  FStartRowDef := BytesOfRange(FLoad.Bytes, st.Core.RowDef.Raw);
  FNeedDelim := False;
  FRawOpen := False;
end;

// After a stretch, before the file's bytes from APos, where paragraph ANext begins: the
// reader's state as it was there - the row definition, each group that was open (with the
// properties it saved, which come back when the file closes it) and the properties in
// effect. What belongs to tables (the row definition, "in a table") only before a paragraph
// of a table: before any other it ends unused in the file too, and the system's RichEdit
// drops a paragraph that follows a row definition or an \intbl with no cell.
procedure TRtfWriter.RestoreAt(APos: Int64; ANext: Integer);
var
  st: TTyRtfState;
  cur, def: RawByteString;
  k: Integer;
  table: Boolean;
begin
  if not FLoad.StateAt(APos, st) then
    raise ETyRichRtfWrite.CreateFmt('RTF writer: no reader state at byte %d', [APos]);
  table := (ANext < FParaCount) and (FDoc.CellAt(ANext) <> nil);
  if table then
  begin
    // the row definition in effect: only when it is not the one the output already left
    if FWroteRow then cur := FLastRowDef else cur := FStartRowDef;
    def := BytesOfRange(FLoad.Bytes, st.Core.RowDef.Raw);
    if (def <> '') and not SameBytes(def, cur) then PutRaw(def);
  end;
  for k := 1 to st.Core.Depth - 1 do
  begin
    PutRaw(TyRtfStateWords(st, FLoad.Bytes, k, table));
    PutB(Ord('{'));
  end;
  PutRaw(TyRtfStateWords(st, FLoad.Bytes, -1, table));
  // the last of them is a control word: its delimiter
  PutB(Ord(' '));
  FNeedDelim := False;
  FRawOpen := False;
end;

// The stretch reached the end of the body; what follows the last paragraph in the file may
// close groups that the file's last paragraphs had opened.
procedure TRtfWriter.BalanceTrailer;
var
  st: TTyRtfState;
  d: Integer;
begin
  if FLoad.StateAt(FTrailer.Start, st) then
    for d := 2 to st.Core.Depth do PutB(Ord('{'));
end;

procedure TRtfWriter.AddStretchInfo(AFirst, ACount: Integer; AOutStart: Int64);
begin
  if FStretchN = Length(FInfo.Stretches) then SetLength(FInfo.Stretches, FStretchN * 2 + 4);
  FInfo.Stretches[FStretchN].FirstPara := AFirst;
  FInfo.Stretches[FStretchN].ParaCount := ACount;
  FInfo.Stretches[FStretchN].OutStart := AOutStart;
  FInfo.Stretches[FStretchN].OutStop := OutPos;
  Inc(FStretchN);
  Inc(FInfo.RewrittenParas, ACount);
end;

procedure TRtfWriter.SaveFile;
var
  k: Integer;
  outStart: Int64;
  bytes: TBytes;
  item: TPlanItem;
begin
  PlanFile;
  bytes := FLoad.Bytes;
  WriteHeaderOfFile;
  FInfo.HeaderStop := OutPos;
  for k := 0 to FPlanN - 1 do
  begin
    item := FPlan[k];
    if item.Stretch then
    begin
      outStart := OutPos;
      LeaveGroupsAt(item.Start);
      WriteStretch(item.First, item.Count);
      if item.Stop >= 0 then RestoreAt(item.Stop, item.First + item.Count) else BalanceTrailer;
      AddStretchInfo(item.First, item.Count, outStart);
    end
    else
    begin
      Put(@bytes[item.Start], item.Stop - item.Start);
      Inc(FInfo.VerbatimParas, item.Count);
      FNeedDelim := False;
      FRawOpen := False;
    end;
  end;
  FInfo.TrailerStart := OutPos;
  if Length(bytes) > FTrailer.Start then
    Put(@bytes[FTrailer.Start], Length(bytes) - FTrailer.Start);
end;

procedure TRtfWriter.SaveOurs;
var
  start: Int64;
begin
  EnsureTables;
  CharInfo(FDoc.DefaultCharFormatId);
  FDoc.Text.WalkParas(0, @NoteWalk);
  FinishTables;
  WriteHeaderOfOurs;
  FInfo.HeaderStop := OutPos;
  start := OutPos;
  WriteStretch(0, FParaCount);
  AddStretchInfo(0, FParaCount, start);
  FInfo.TrailerStart := OutPos;
  Sym('}');
  NewLine;
end;

procedure TRtfWriter.Run;
begin
  FParaCount := FDoc.Text.ParaCount;
  if FLoad <> nil then SaveFile else SaveOurs;
  Flush;
  SetLength(FInfo.Stretches, FStretchN);
end;

// ---- the entry points ----

procedure TyRichSaveRtf(ADoc: TTyRichDocument; AStream: TStream; out AInfo: TTyRtfWriteInfo);
var
  w: TRtfWriter;
begin
  AInfo := Default(TTyRtfWriteInfo);
  if ADoc.Incomplete then
    raise ETyRichRtfWrite.Create(
      'This document holds only a part of its file (the load was cancelled): it cannot be saved as RTF');
  if ADoc.Loading then
    raise ETyRichRtfWrite.Create(
      'This document is still being loaded: it cannot be saved before the load has ended');
  w := TRtfWriter.Create(ADoc, AStream);
  try
    w.Run;
    AInfo := w.Info;
  finally
    w.Free;
  end;
end;

procedure TyRichSaveRtf(ADoc: TTyRichDocument; AStream: TStream);
var
  info: TTyRtfWriteInfo;
begin
  TyRichSaveRtf(ADoc, AStream, info);
end;

end.
