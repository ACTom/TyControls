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
//
// What is written from the model is as long as the model: the save goes through those
// paragraphs in walks of the text that hand out each paragraph's value and text together,
// streams through one buffer, and - asked to - reports how far it is and stops when told
// (TTyRtfSaveProgress).
//
// What the model keeps of a file beside what it understands - the fragments of a format's
// Extra, an object's bytes, a row's RawFormat - means something only next to the header it
// was read with: they name fonts, colours, styles and lists by the numbers of that file's
// tables. They are written back into that file. (For whoever carries content from one
// document to another: such fragments cannot simply go along.)

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
{$inline on}

interface

uses
  Classes, SysUtils, Graphics, LCLType, tyControls.RichEdit.Text, tyControls.RichEdit.Model,
  tyControls.RichEdit.RtfRead;

type
  ETyRichRtfWrite = class(ETyRichRtf);
  // A save was cancelled by its progress callback. An EAbort: it shows no message when it
  // reaches the application's exception handler.
  ETyRichSaveCancelled = class(EAbort);

  // A save's progress: ADone of ATotal paragraphs are in the output. Called about every
  // 256 KB written, and every 65536 paragraphs while the save plans (it writes nothing
  // then, and ADone stays 0) - not at all for a save shorter than that. False cancels the
  // save: it raises ETyRichSaveCancelled and leaves a part of the file in the stream. The
  // handler may let the application handle its messages; it must not change the document
  // or put other content into it.
  TTyRtfSaveProgress = function(ADone, ATotal: Int64): Boolean of object;

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

// Writes ADoc to AStream as RTF.
//
// Raises ETyRichRtfWrite before anything is written when ADoc is Incomplete (a cancelled
// load: the rest of the file is not in it) or still Loading (finish the load first:
// TTyRtfLoad.Step), and when a paragraph that has to be written from the model lies in a
// table row that holds a nested table (TTyRichRow.HoldsNestedTable; the model lets no
// command change such a row). Any other exception - the stream's, ETyRichSaveCancelled -
// leaves a part of the file in the stream: save to a temporary file and put it in the
// place of the real one when this has returned.
//
// AOnProgress: see TTyRtfSaveProgress. Without it a file that was not changed goes out in
// three writes; with it in pieces of 256 KB.
//
// In a rewritten stretch of a file, the table row definition in effect is put back after
// the stretch only before a paragraph of a table (see RestoreAt). A character of a text
// file that was read as U+FFFD (bytes that are no text in the file's encoding) is written
// as U+FFFD: the bytes it stood for are not in the RTF.
procedure TyRichSaveRtf(ADoc: TTyRichDocument; AStream: TStream;
  AOnProgress: TTyRtfSaveProgress = nil); overload;
procedure TyRichSaveRtf(ADoc: TTyRichDocument; AStream: TStream; out AInfo: TTyRtfWriteInfo;
  AOnProgress: TTyRtfSaveProgress = nil); overload;

implementation

uses
  tyControls.RichEdit.TextIO;

const
  OutBufSize = 64 * 1024;
  // how often the progress callback is asked: every so many bytes written, and while the
  // save plans every so many paragraphs (a power of two)
  ProgressBytes = 256 * 1024;
  PlanEvery = 65536;
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
    PnUc: Boolean;                   // a fragment of {\*\pn} holds a \uN
  end;
  PParaInfo = ^TParaInfo;

  TPlanItem = record
    Stretch: Boolean;
    First, Count: Integer;   // paragraphs
    Start, Stop: Int64;      // a block: its bytes; a stretch: the file position it begins at
                             // and the one the file goes on from (-1: the end of the body)
    Look: Boolean;           // a stretch: a font of it gets its charset from the text
  end;

  TRtfWriter = class
  private
    FDoc: TTyRichDocument;
    FLoad: TTyRtfLoad;
    FStream: TStream;
    FPool: TTyFormatPool;
    FInfo: TTyRtfWriteInfo;
    FStretchN: Integer;
    // progress
    FOnProgress: TTyRtfSaveProgress;
    FProgressAt: Int64;      // bytes written when the callback was last asked
    FDone: Int64;            // paragraphs in the output
    FCopyParas, FCopyBytes, FCopyStart: Int64;   // a block of the file that is going out
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
    // Text with no font (a font number the file's table lacks) is written with a number of
    // its own - without \f it would take the file's default font. The number is an entry
    // with no name: the file's own when it has one, else one this save adds (FNoFontDefine)
    // when such text is written (FNoFontUsed), so that the next save finds the number taken.
    FNoFontNum: Integer;
    FNoFontUsed, FNoFontDefine: Boolean;
    FColors: array of TColorRec;
    FColorN, FOldColorN: Integer;
    FDefNames: array of TDefName;
    FDefNameN: Integer;
    // What is known of each format id, made the first time the id is met. The arrays hold
    // pointers: a record is handed out and used while other ids are met (a list item's
    // number looks at the paragraphs before it), and an array of records would move under
    // the pointer when it grows.
    FChars: array of PCharInfo;
    FParas: array of PParaInfo;
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
    FStretchLook: Boolean;   // the text of the stretch being planned has to be looked at
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
    // the paragraph written last: its list and its number in it
    FNumPara, FNum: Integer;
    FNumList: TTyListFormat;
    FUc: Integer;            // the \uc the file has in effect where the stretch begins
    FHavePrev: Boolean;      // a paragraph of the stretch is written and not yet ended
    FPrevCell: TTyRichCell;  // its cell
    // output
    procedure Flush;
    procedure Tick;
    procedure PlanTick(AIndex: Integer); inline;
    procedure Put(P: PByte; ACount: Int64);
    procedure PutB(B: Byte); inline;
    procedure PutS(const S: string);
    procedure PutInt(AValue: Int64);
    procedure PutRaw(const S: RawByteString);
    function OutPos: Int64;
    procedure Word(const AName: string);
    procedure WordN(const AName: string; AValue: Int64);
    procedure Sym(const S: string);
    procedure Lit(B: Byte);
    procedure Raw(const S: RawByteString);
    procedure RawUnder(const S: RawByteString; AUc: Integer);
    procedure Fragment(const S: RawByteString);
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
    function Unsettled(ADefName: Integer): Boolean;
    procedure ReadPara(AIndex: Integer; AData: Pointer; out AFormat: TTyParaFormatId;
      out ARuns: TTyRunArray; out ACell: TTyRichCell);
    procedure Note(AIndex: Integer; AFormat: TTyParaFormatId; const ARuns: TTyRunArray;
      ACell: TTyRichCell);
    procedure NotePara(AIndex: Integer; AData: Pointer);
    procedure LookPara(AIndex: Integer; AData: Pointer; AText: PByte; ALen: PtrInt;
      var AContinue: Boolean);
    procedure FinishTables;
    procedure WriteFontEntry(const F: TFontRec; AAnsiCp: Integer);
    procedure WriteNoFontEntry;
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
    procedure StretchPara(AIndex: Integer; AData: Pointer; AText: PByte; ALen: PtrInt;
      var AContinue: Boolean);
    procedure StartRow(ACell: TTyRichCell);
    procedure EndPara(ACell, ANext: TTyRichCell);
    procedure WriteRowDef(ARow: TTyRichRow);
    procedure WritePara(AIndex: Integer; AFormat: TTyParaFormatId; const ARuns: TTyRunArray;
      AInCell: Boolean; AText: PByte; ALen: PtrInt);
    procedure WriteParaFormat(AInfo: PParaInfo; AInCell: Boolean; AFirstFont, ANumber: Integer);
    procedure WritePnWords(const AList: TTyListFormat);
    procedure WritePnText(AInfo: PParaInfo; AFirstFont, ANumber: Integer);
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
    destructor Destroy; override;
    procedure Run;
    property Info: TTyRtfWriteInfo read FInfo;
  end;

var
  // bytes of text that are written as they are: printable ASCII but \ { }
  PlainByte: array[Byte] of Boolean;

procedure InitPlainBytes;
var
  b: Integer;
begin
  for b := 0 to 255 do
    PlainByte[b] := (b >= $20) and (b <= $7E) and not (b in [Ord('\'), Ord('{'), Ord('}')]);
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

// A kept group that holds a \uN: how many of the bytes after it are its fallback is said by
// the \uc in effect, not by the group, so it reads the same only under the \uc it was read
// under.
function HoldsUnicodeEscape(const S: RawByteString): Boolean;
var
  i, n: Integer;
begin
  Result := False;
  n := Length(S);
  if (n < 4) or (S[1] <> '{') then Exit;
  i := 2;
  while i < n do
  begin
    if S[i] <> '\' then
    begin
      Inc(i);
      Continue;
    end;
    // \u123 or \u-123; any other word or symbol is passed over (\\ is a symbol)
    if (S[i + 1] = 'u') and (i + 2 <= n) and
       ((S[i + 2] in ['0'..'9']) or ((S[i + 2] = '-') and (i + 3 <= n) and (S[i + 3] in ['0'..'9']))) then
      Exit(True);
    Inc(i, 2);
  end;
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
  FUc := 1;
  SetLength(FBuf, OutBufSize);
end;

destructor TRtfWriter.Destroy;
var
  i: Integer;
begin
  for i := 0 to High(FChars) do
    if FChars[i] <> nil then Dispose(FChars[i]);
  for i := 0 to High(FParas) do
    if FParas[i] <> nil then Dispose(FParas[i]);
  inherited Destroy;
end;

procedure TRtfWriter.Flush;
begin
  if FBufLen = 0 then Exit;
  FStream.WriteBuffer(FBuf[0], FBufLen);
  Inc(FWritten, FBufLen);
  FBufLen := 0;
  if Assigned(FOnProgress) and (FWritten - FProgressAt >= ProgressBytes) then Tick;
end;

// Asks the progress callback: how many paragraphs are in the output - of a block of the
// file that is going out, its share by bytes. False from it ends the save.
procedure TRtfWriter.Tick;
var
  done: Int64;
begin
  FProgressAt := FWritten;
  done := FDone;
  if (FCopyBytes > 0) and (FWritten > FCopyStart) then
    Inc(done, FCopyParas * (FWritten - FCopyStart) div FCopyBytes);
  if done > FParaCount then done := FParaCount;
  if not FOnProgress(done, FParaCount) then
    raise ETyRichSaveCancelled.Create('The save was cancelled');
end;

// While the save plans nothing is written: the callback is asked every so many paragraphs.
procedure TRtfWriter.PlanTick(AIndex: Integer);
begin
  if Assigned(FOnProgress) and (AIndex and (PlanEvery - 1) = PlanEvery - 1) then Tick;
end;

procedure TRtfWriter.Put(P: PByte; ACount: Int64);
const
  BigChunk = 256 * 1024 * 1024;
var
  n, chunk: Int64;
begin
  if ACount <= 0 then Exit;
  if ACount >= OutBufSize then
  begin
    // a block of the file goes out as it is, not through the buffer: in one write - or,
    // when the progress is watched, in pieces with the callback between them
    Flush;
    if Assigned(FOnProgress) then chunk := ProgressBytes else chunk := BigChunk;
    while ACount > 0 do
    begin
      n := ACount;
      if n > chunk then n := chunk;
      FStream.WriteBuffer(P^, n);
      Inc(FWritten, n);
      Inc(P, n);
      Dec(ACount, n);
      if Assigned(FOnProgress) and (FWritten - FProgressAt >= ProgressBytes) then Tick;
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

// A number's digits, straight into the buffer (a save writes one for every character that
// is not ASCII: no string is made for it).
procedure TRtfWriter.PutInt(AValue: Int64);
var
  digits: array[0..19] of Byte;
  n: Integer;
  v: QWord;
begin
  if AValue < 0 then
  begin
    PutB(Ord('-'));
    v := QWord(-(AValue + 1)) + 1;
  end
  else
    v := AValue;
  n := 0;
  repeat
    digits[n] := Ord('0') + v mod 10;
    v := v div 10;
    Inc(n);
  until v = 0;
  while n > 0 do
  begin
    Dec(n);
    PutB(digits[n]);
  end;
end;

procedure TRtfWriter.WordN(const AName: string; AValue: Int64);
begin
  PutB(Ord('\'));
  PutS(AName);
  PutInt(AValue);
  FNeedDelim := True;
  FRawOpen := False;
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

// A kept group, read under \ucAUc. What is written here is under \uc1 (one fallback
// character after each \uN); the group's own \uN have as many as AUc says, so it goes
// between that \uc and ours. (One control word kept as an object holds no \uN.)
procedure TRtfWriter.RawUnder(const S: RawByteString; AUc: Integer);
begin
  if (AUc = 1) or (S = '') or (S[1] <> '{') then
  begin
    Raw(S);
    Exit;
  end;
  WordN('uc', AUc);
  Raw(S);
  Word('uc1');
end;

// A fragment of a format's Extra. The format does not say under which \uc a group among
// them was read: it is taken to be the one in effect where the stretch begins in the file,
// which is the paragraph's own in all but files that change \uc between paragraphs.
procedure TRtfWriter.Fragment(const S: RawByteString);
begin
  if (FUc <> 1) and HoldsUnicodeEscape(S) then RawUnder(S, FUc) else Raw(S);
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
    // an entry with no name and no charset is what text with no font is written in
    if (FNoFontNum < 0) and (f.Name = '') and (f.Charset < 0) then FNoFontNum := f.Num;
  end;
  // the reader passes over entries it cannot read (and what is inside them): their numbers
  // are taken all the same, so new fonts are numbered above every \fN of the table's bytes
  i := scan.FontTableHighest;
  if i >= FNextFontNum then FNextFontNum := i + 1;
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
  if FChars[AId] = nil then
  begin
    New(Result);
    Result^ := Default(TCharInfo);
    FChars[AId] := Result;
  end;
  Result := FChars[AId];
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
  if FParas[AId] = nil then
  begin
    New(Result);
    Result^ := Default(TParaInfo);
    FParas[AId] := Result;
  end;
  Result := FParas[AId];
  if Result^.Seen then Exit;
  Result^.Seen := True;
  Result^.Fmt := FPool.ParaFormat(AId);
  Result^.PnFont := -1;
  Result^.PnBefore := '';
  Result^.PnAfter := '';
  Result^.PnUc := False;
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
          if HoldsUnicodeEscape(frag) then Result^.PnUc := True;
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

// A font name with no charset whose charset the text written in it can still say (kana
// settles it: Japanese text has ideographs too).
function TRtfWriter.Unsettled(ADefName: Integer): Boolean;
begin
  Result := not FDefNames[ADefName].Known and not FDefNames[ADefName].Kana;
end;

// What paragraph AIndex holds. AData is its value as a walk of the text hands it out: read
// without a lookup. A paragraph with no value in a document that parses on demand is one
// of the file's that was never parsed (a stretch takes it along: its row, the way back to
// a clean place); it is read by its index, which parses it.
procedure TRtfWriter.ReadPara(AIndex: Integer; AData: Pointer; out AFormat: TTyParaFormatId;
  out ARuns: TTyRunArray; out ACell: TTyRichCell);
begin
  if FDoc.ReadValue(AData, AFormat, ARuns, ACell) then Exit;
  AFormat := FDoc.ParaFormatOf(AIndex);
  ARuns := FDoc.RunsOf(AIndex);
  ACell := FDoc.CellAt(AIndex);
end;

// A paragraph that will be written from the model: the fonts and colours it needs.
procedure TRtfWriter.Note(AIndex: Integer; AFormat: TTyParaFormatId; const ARuns: TTyRunArray;
  ACell: TTyRichCell);
var
  j: Integer;
  ci: PCharInfo;
  pi: PParaInfo;
begin
  EnsureTables;
  // A row that holds a nested table is more in the file than in the model: written from
  // the model it would lose the inner table without a word. The model lets nothing change
  // in such a row, so this is not reached through commands; it is asked here all the same,
  // while nothing has been written yet.
  if (FLoad <> nil) and (ACell <> nil) and ACell.Row.HoldsNestedTable then
    raise ETyRichRtfWrite.CreateFmt('RTF writer: paragraph %d is in a table row that holds ' +
      'a nested table and has changed: written from the model, the row would lose that table',
      [AIndex]);
  for j := 0 to High(ARuns) do
  begin
    ci := CharInfo(ARuns[j].Format);
    if ci^.Font = -1 then FNoFontUsed := True;
    // the text written in such a font is looked at when the plan is made (LookPara)
    if (ci^.DefName >= 0) and Unsettled(ci^.DefName) then FStretchLook := True;
  end;
  pi := ParaInfo(AFormat);
  // a bullet made here is the Symbol font's
  if (pi^.Mode = lmGen) and (pi^.Fmt.List.Kind = lkBullet) then FSymbolNeeded := True;
end;

procedure TRtfWriter.NotePara(AIndex: Integer; AData: Pointer);
var
  pf: TTyParaFormatId;
  runs: TTyRunArray;
  cell: TTyRichCell;
begin
  ReadPara(AIndex, AData, pf, runs, cell);
  Note(AIndex, pf, runs, cell);
end;

// One step of the walk over a stretch whose text is looked at: what the text written in a
// font that names no charset says about it.
procedure TRtfWriter.LookPara(AIndex: Integer; AData: Pointer; AText: PByte; ALen: PtrInt;
  var AContinue: Boolean);
var
  pf: TTyParaFormatId;
  runs: TTyRunArray;
  cell: TTyRichCell;
  p, n: PtrInt;
  ch: Int64;
  r, d: Integer;
  code: Cardinal;
  any: Boolean;
begin
  PlanTick(AIndex);
  // (in a document of our own a paragraph with no value is plain, and was not noted)
  if (AData = nil) and (FLoad = nil) then Exit;
  ReadPara(AIndex, AData, pf, runs, cell);
  any := False;
  for r := 0 to High(runs) do
  begin
    d := CharInfo(runs[r].Format)^.DefName;
    if (d >= 0) and Unsettled(d) then any := True;
  end;
  if not any then Exit;
  p := 0;
  ch := 0;
  r := 0;
  while p < ALen do
  begin
    while (r < High(runs)) and (runs[r + 1].Start <= ch) do Inc(r);
    n := NextChar(AText + p, ALen - p, code);
    d := CharInfo(runs[r].Format)^.DefName;
    if d >= 0 then
      with FDefNames[d] do Classify(code, Kana, Hangul, Han);
    Inc(p, n);
    Inc(ch);
  end;
  // when no name is left that the text could still say more about, the walk can end
  for d := 0 to FDefNameN - 1 do
    if Unsettled(d) then Exit;
  AContinue := False;
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
  else if FNoFontNum < 0 then
  begin
    // the file has no entry without a name: the first number free (every font this save
    // adds has its number by now), defined when it is used
    FNoFontNum := FNextFontNum;
    FNoFontDefine := FNoFontUsed;
  end;
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

// {\fN\fnil ;} - the entry of text with no font.
procedure TRtfWriter.WriteNoFontEntry;
begin
  Sym('{');
  WordN('f', FNoFontNum);
  Word('fnil');
  Sym(' ;}');
end;

procedure TRtfWriter.WriteFonts(AFrom: Integer; AWhole: Boolean; AAnsiCp: Integer);
var
  order: array of Integer;
  i, j, t: Integer;
  first: Boolean;
begin
  first := False;
  if AWhole then
  begin
    Sym('{\fonttbl');
    // a file with no font table and no \deff: its text has no font, and a reader takes
    // the first font of a table for such text - so the first is the one with no name
    first := (FLoad <> nil) and (FLoad.Scan.DefaultFont < 0);
    if first then WriteNoFontEntry;
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
  if FNoFontDefine and not first then WriteNoFontEntry;
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
    if (FFontN > FOldFontN) or FNoFontDefine then
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
  FPlan[FPlanN].Look := False;
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
  FStretchLook := False;
  FStretchFirst := a;
  FStretchX := x;
  // (paragraphs of the file the walk has passed: read by their index)
  for k := a to AIndex - 1 do NotePara(k, nil);
end;

procedure TRtfWriter.CloseStretch(AIndex: Integer; AStop: Int64);
begin
  AddItem(True, FStretchFirst, AIndex - FStretchFirst, FStretchX, AStop);
  FPlan[FPlanN - 1].Look := FStretchLook;
  FInStretch := False;
end;

procedure TRtfWriter.PlanPara(AIndex: Integer; AData: Pointer; ASrcOffset, ASrcBytes: Int64;
  var AContinue: Boolean);
var
  own: Boolean;
begin
  PlanTick(AIndex);
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
    NotePara(AIndex, AData);
end;

procedure TRtfWriter.PlanFile;
var
  k: Integer;
  item: TPlanItem;
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
  // the text of the stretches that have a font whose charset the text decides
  for k := 0 to FPlanN - 1 do
  begin
    item := FPlan[k];
    if item.Stretch and item.Look and (item.Count > 0) then
      FDoc.Text.WalkParaTexts(item.First, item.First + item.Count - 1, @LookPara);
  end;
  FinishTables;
end;

procedure TRtfWriter.NoteWalk(AIndex: Integer; AData: Pointer; ASrcOffset, ASrcBytes: Int64;
  var AContinue: Boolean);
begin
  PlanTick(AIndex);
  // (a paragraph with no value is plain: the default formats, noted once)
  if AData <> nil then NotePara(AIndex, AData);
end;

// ---- paragraphs from the model ----

// Paragraphs AFirst .. AFirst + ACount - 1 from the model, in one walk of the text that
// hands out each paragraph's value and text together (StretchPara).
procedure TRtfWriter.WriteStretch(AFirst, ACount: Integer);
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
  // (the stretch starts and ends between rows: the plan saw to that)
  FHavePrev := False;
  FPrevCell := nil;
  FDoc.Text.WalkParaTexts(AFirst, AFirst + ACount - 1, @StretchPara);
  EndPara(FPrevCell, nil);
end;

// One paragraph of a stretch. How a paragraph ends depends on the one after it (\par inside
// a cell, \cell at its end, \row after the row's last cell), so each one first ends the
// paragraph before it.
procedure TRtfWriter.StretchPara(AIndex: Integer; AData: Pointer; AText: PByte; ALen: PtrInt;
  var AContinue: Boolean);
var
  pf: TTyParaFormatId;
  runs: TTyRunArray;
  cell: TTyRichCell;
begin
  ReadPara(AIndex, AData, pf, runs, cell);
  if FHavePrev then EndPara(FPrevCell, cell);
  if (cell <> nil) and (not FHavePrev or (FPrevCell = nil) or (FPrevCell.Row <> cell.Row)) then
    StartRow(cell);
  WritePara(AIndex, pf, runs, cell <> nil, AText, ALen);
  FPrevCell := cell;
  FHavePrev := True;
  Inc(FDone);
end;

// A row begins: its definition. A row is all its cells, each in its place, and the model
// lets a cell lose its only paragraph: such a cell is written empty - here those before
// the cell of the row's first paragraph, in EndPara the others - or the cells after it
// would move left.
procedure TRtfWriter.StartRow(ACell: TTyRichCell);
var
  k: Integer;
begin
  WriteRowDef(ACell.Row);
  if ACell.Index > 0 then
  begin
    Word('pard');
    Word('intbl');
    for k := 1 to ACell.Index do Word('cell');
  end;
end;

// The end of a paragraph in ACell (nil: in no table) that ANext's paragraph follows (nil:
// one outside a table, or none).
procedure TRtfWriter.EndPara(ACell, ANext: TTyRichCell);
var
  k: Integer;
begin
  if (ACell = nil) or (ANext = ACell) then
  begin
    Word('par');
    NewLine;
    Exit;
  end;
  Word('cell');
  if (ANext = nil) or (ANext.Row <> ACell.Row) then
  begin
    // the cells after the row's last paragraph
    for k := ACell.Index + 1 to ACell.Row.CellCount - 1 do Word('cell');
    Word('row');
    NewLine;
    // what follows a row starts from \pard
    FCurPara := -1;
  end
  else
    // the cells between this paragraph's and the next one's
    for k := ACell.Index + 1 to ANext.Index - 1 do Word('cell');
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

procedure TRtfWriter.WritePara(AIndex: Integer; AFormat: TTyParaFormatId;
  const ARuns: TTyRunArray; AInCell: Boolean; AText: PByte; ALen: PtrInt);
var
  pi: PParaInfo;
  p, q, stop, n: PtrInt;
  ch, runEnd: Int64;
  r, firstFont, number: Integer;
  code: Cardinal;
begin
  pi := ParaInfo(AFormat);
  firstFont := -1;
  if Length(ARuns) > 0 then firstFont := FontNumOf(ARuns[0].Format);
  // The item's number - and for every paragraph, which list it is of: the next item's
  // number goes on from it (ListNumber). A number that is not written (Word's list table
  // says it) is worked out only when that costs nothing.
  number := 0;
  if pi^.Fmt.List.Kind in [lkNone, lkBullet] then
  begin
    FNumPara := AIndex;
    FNumList := pi^.Fmt.List;
    FNum := 0;
  end
  else if (pi^.Mode in [lmPn, lmGen]) or (FNumPara = AIndex - 1) then
    number := ListNumber(AIndex, pi^.Fmt.List)
  else
    FNumPara := -2;
  if (AFormat <> FCurPara) or (AInCell <> FCurInCell) then
  begin
    WriteParaFormat(pi, AInCell, firstFont, number);
    FCurPara := AFormat;
    FCurInCell := AInCell;
  end
  else if (pi^.Mode in [lmPn, lmGen]) and (pi^.Fmt.List.Kind <> lkNone) then
    // the same list goes on: only the item's own text
    WritePnText(pi, firstFont, number);
  p := 0;
  ch := 0;
  for r := 0 to High(ARuns) do
  begin
    if r < High(ARuns) then runEnd := ARuns[r + 1].Start else runEnd := High(Int64);
    if ARuns[r].Format <> FCurChar then WriteCharFormat(ARuns[r].Format);
    if ARuns[r].Obj <> nil then
    begin
      WriteObject(ARuns[r].Obj);
      // its one character
      if p < ALen then
      begin
        Inc(p, NextChar(AText + p, ALen - p, code));
        Inc(ch);
      end;
      Continue;
    end;
    while (ch < runEnd) and (p < ALen) do
      if PlainByte[AText[p]] and not FCurSymbol then
      begin
        // printable ASCII goes out as it is, a run of it at once
        q := p + 1;
        stop := ALen;
        if runEnd - ch < stop - p then stop := p + (runEnd - ch);
        while (q < stop) and PlainByte[AText[q]] do Inc(q);
        // (what Lit does before a byte of text)
        if FNeedDelim then
          PutB(Ord(' '))
        else if FRawOpen then
          PutS('{}');
        FNeedDelim := False;
        FRawOpen := False;
        Put(AText + p, q - p);
        Inc(ch, q - p);
        p := q;
      end
      else
      begin
        n := NextChar(AText + p, ALen - p, code);
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
// right before it. Inside a stretch the paragraph before was written just now, and its
// list and number are known (WritePara notes them for every paragraph); only a stretch's
// first paragraph has to look back at the paragraphs before it, each by a lookup - at most
// MaxListWalk of them (the number is only text for readers that do not number themselves).
function TRtfWriter.ListNumber(AIndex: Integer; const AList: TTyListFormat): Integer;
var
  k, steps: Integer;
begin
  Result := AList.StartAt;
  if Result <= 0 then Result := 1;
  if FNumPara = AIndex - 1 then
  begin
    if SameList(FNumList, AList) then Result := FNum + 1;
  end
  else
  begin
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
procedure TRtfWriter.WritePnText(AInfo: PParaInfo; AFirstFont, ANumber: Integer);
var
  font, i: Integer;
  s: string;
begin
  Sym('{');
  Word('pntext');
  // the bullet's or number's text as the file has it may hold \uN (see Fragment)
  if (AInfo^.Mode <> lmGen) and AInfo^.PnUc and (FUc <> 1) then WordN('uc', FUc);
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
    s := ListNumberText(AInfo^.Fmt.List.Kind, ANumber);
    for i := 1 to Length(s) do Lit(Ord(s[i]));
    if AInfo^.Mode = lmGen then Lit(Ord('.')) else RawText(AInfo^.PnAfter);
  end;
  Word('tab');
  Sym('}');
end;

// \pard and everything of the paragraph format: the list, the fragments of Extra where the
// reader finds them again, then the properties the model has (after the fragments, so that
// the model's value is the one that holds).
procedure TRtfWriter.WriteParaFormat(AInfo: PParaInfo; AInCell: Boolean; AFirstFont,
  ANumber: Integer);
const
  TabAlignWord: array[TTyTabAlign] of string = ('', 'tqc', 'tqr', 'tqdec');
  TabLeaderWord: array[TTyTabLeader] of string = ('', 'tldot', 'tlhyph', 'tlul', 'tlth', 'tleq');
var
  i: Integer;
  inPn, pnDone, pnUc: Boolean;
  list: TTyListFormat;

  procedure ClosePn;
  begin
    Sym('}');
    if pnUc then Word('uc1');
    inPn := False;
  end;

begin
  Word('pard');
  if AInCell then Word('intbl');
  list := AInfo^.Fmt.List;
  if (AInfo^.Mode in [lmPn, lmGen]) and (list.Kind <> lkNone) then
    WritePnText(AInfo, AFirstFont, ANumber);
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
  // a {\pntxtb ...} with a \uN in it: the whole {\*\pn} goes between the file's \uc and ours
  pnUc := AInfo^.PnUc and (FUc <> 1);
  for i := 0 to AInfo^.Fmt.Extra.Count - 1 do
  begin
    // \ls and \ilvl name a list of the file's table: only while that is still the list
    if (AInfo^.Kinds[i] in [pekLs, pekIlvl]) and (AInfo^.Mode <> lmLs) then Continue;
    if AInfo^.Kinds[i] = pekPn then
    begin
      if not inPn then
      begin
        if pnUc then WordN('uc', FUc);
        Sym('{\*');
        Word('pn');
        if not pnDone and (AInfo^.Mode = lmPn) then WritePnWords(list);
        pnDone := True;
        inPn := True;
      end;
      Raw(AInfo^.Fmt.Extra.Item(i));
    end
    else
    begin
      if inPn then ClosePn;
      Fragment(AInfo^.Fmt.Extra.Item(i));
    end;
  end;
  if inPn then ClosePn;
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
  for i := 0 to ci^.Fmt.Extra.Count - 1 do Fragment(ci^.Fmt.Extra.Item(i));
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

// \uN? for one UTF-16 code unit, N signed as RTF has it. A text that is not ASCII is one
// of these for every character, so its bytes go straight into the buffer: no string, no
// call a byte.
procedure TRtfWriter.WriteUnit(AUnit: Cardinal);
var
  digits: array[0..4] of Byte;
  n, k: Integer;
  w, q: Cardinal;
  p: PByte;
begin
  // at most \u-32768? - nine bytes
  if FBufLen + 9 > OutBufSize then Flush;
  p := @FBuf[FBufLen];
  p[0] := Ord('\');
  p[1] := Ord('u');
  k := 2;
  w := AUnit and $FFFF;
  if w > 32767 then
  begin
    p[k] := Ord('-');
    Inc(k);
    w := 65536 - w;
  end;
  n := 0;
  repeat
    // (w div 10, exact below 81920)
    q := (w * 52429) shr 19;
    digits[n] := Ord('0') + (w - q * 10);
    w := q;
    Inc(n);
  until w = 0;
  while n > 0 do
  begin
    Dec(n);
    p[k] := digits[n];
    Inc(k);
  end;
  p[k] := Ord('?');
  Inc(FBufLen, k + 1);
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
    RawUnder(TTyRichOpaque(AObj).Bytes, AObj.RawUc)
  else if AObj is TTyRichPicture then
  begin
    if TTyRichPicture(AObj).RawRtf <> '' then RawUnder(TTyRichPicture(AObj).RawRtf, AObj.RawUc)
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
  FUc := 1;
  if not FLoad.StateAt(APos, st) then Exit;
  FUc := st.Core.Props.Uc;
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
      // (for the progress: the block's paragraphs count as its bytes go out)
      FCopyParas := item.Count;
      FCopyBytes := item.Stop - item.Start;
      FCopyStart := OutPos;
      Put(@bytes[item.Start], item.Stop - item.Start);
      FCopyBytes := 0;
      Inc(FDone, item.Count);
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
  FStretchLook := False;
  FDoc.Text.WalkParas(0, @NoteWalk);
  if FStretchLook then FDoc.Text.WalkParaTexts(0, FParaCount - 1, @LookPara);
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
  // one read scope for the whole save: the cells, rows and objects read for a paragraph
  // are used while its neighbours are read, and a read that parses could otherwise send
  // the interval they belong to back to unparsed
  FDoc.BeginRead;
  try
    if FLoad <> nil then SaveFile else SaveOurs;
    Flush;
  finally
    FDoc.EndRead;
  end;
  SetLength(FInfo.Stretches, FStretchN);
end;

// ---- the entry points ----

procedure TyRichSaveRtf(ADoc: TTyRichDocument; AStream: TStream; out AInfo: TTyRtfWriteInfo;
  AOnProgress: TTyRtfSaveProgress);
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
    w.FOnProgress := AOnProgress;
    w.Run;
    AInfo := w.Info;
  finally
    w.Free;
  end;
end;

procedure TyRichSaveRtf(ADoc: TTyRichDocument; AStream: TStream; AOnProgress: TTyRtfSaveProgress);
var
  info: TTyRtfWriteInfo;
begin
  TyRichSaveRtf(ADoc, AStream, info, AOnProgress);
end;

initialization
  InitPlainBytes;
end.
