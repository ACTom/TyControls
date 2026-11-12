unit test.richedit.rtfwrite;

{ Writing RTF (tyControls.RichEdit.RtfWrite). Two promises: a file opened and saved without
  a change is the same file, byte for byte; and in a file that was changed, everything that
  was not touched goes back exactly as it was read. Both come out of one way of writing: the
  header, each paragraph (its own bytes while it is still the file's, else rewritten from
  the model, with the reader's state put back before the file's bytes go on) and the trailer.
  The heart is TestEveryParagraphEditedInTurnLeavesTheOthersAlone: every paragraph of every
  sample is changed in turn, the result saved and parsed again, and compared with the parse
  of the original. The samples are tests/fixtures/rtf. }

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  Classes, SysUtils, Graphics, LCLType, fpcunit, testregistry,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.Commands,
  tyControls.RichEdit.RtfRead, tyControls.RichEdit.RtfWrite;

type
  TEditKind = (ekInsert, ekCharFormat, ekParaFormat, ekDelete);

  TTyRtfWriteTest = class(TTestCase)
  private
    procedure CheckEdit(const AName: string; const ABytes: TBytes; AFull: TTyRichDocument;
      APara: Integer; AKind: TEditKind);
    procedure CheckVerbatim(const AMsg: string; ADoc: TTyRichDocument; const ABytes,
      AOut: TBytes; const AInfo: TTyRtfWriteInfo);
    procedure CheckRichEditReads(const AMsg: string; ADoc: TTyRichDocument);
  published
    // the brief
    procedure TestOpenSaveIsByteIdentical;
    procedure TestOwnFilesRoundTrip;
    procedure TestChineseIsWrittenAsUnicodeEscapes;
    procedure TestAnEditAtTheEndOfALazyDocumentRewritesOnlyThatParagraph;
    procedure TestWindowsRichEditReadsWhatWeWrite;
    // the rulings
    procedure TestEveryParagraphEditedInTurnLeavesTheOthersAlone;
    procedure TestAOneParagraphEditRewritesItsStretchOnly;
    procedure TestTheHeaderIsOnlyAddedTo;
    procedure TestEveryFormatFieldSurvivesWriteAndRead;
    procedure TestListsAreWrittenAsRichEditWritesThem;
    procedure TestSavingAnUnchangedBigDocumentCopiesRanges;
    procedure TestTheLastParagraphWithoutATerminator;
    procedure TestRefusesWhatItCannotSave;
  end;

implementation

const
  MB = 1024 * 1024;
  BS = '\';

// A character as UTF-8, made from its number so that this file is ASCII and no string
// literal depends on a code page.
function U(ACode: Cardinal): UTF8String;
begin
  Result := '';
  if ACode < $80 then
    Result := AnsiChar(ACode)
  else if ACode < $800 then
  begin
    SetLength(Result, 2);
    Result[1] := AnsiChar($C0 or (ACode shr 6));
    Result[2] := AnsiChar($80 or (ACode and $3F));
  end
  else if ACode < $10000 then
  begin
    SetLength(Result, 3);
    Result[1] := AnsiChar($E0 or (ACode shr 12));
    Result[2] := AnsiChar($80 or ((ACode shr 6) and $3F));
    Result[3] := AnsiChar($80 or (ACode and $3F));
  end
  else
  begin
    SetLength(Result, 4);
    Result[1] := AnsiChar($F0 or (ACode shr 18));
    Result[2] := AnsiChar($80 or ((ACode shr 12) and $3F));
    Result[3] := AnsiChar($80 or ((ACode shr 6) and $3F));
    Result[4] := AnsiChar($80 or (ACode and $3F));
  end;
end;

// S's bytes as a string of the model (a font name), with no conversion.
function Name8(const S: UTF8String): string;
begin
  Result := '';
  SetLength(Result, Length(S));
  if S <> '' then Move(S[1], Result[1], Length(S));
end;

function ZhZhong: UTF8String; begin Result := U($4E2D); end;
function ZhWen: UTF8String; begin Result := U($6587); end;
// the font name SimSun, in Chinese
function ZhSongTi: string; begin Result := Name8(U($5B8B) + U($4F53)); end;
function Grin: UTF8String; begin Result := U($1F600); end;
function LeftQuote: UTF8String; begin Result := U($201C); end;
function EAcute: UTF8String; begin Result := U($E9); end;
function KanaA: UTF8String; begin Result := U($3042); end;
function HangulHan: UTF8String; begin Result := U($D55C); end;
function NoBreakSpace: UTF8String; begin Result := U($A0); end;
function NoBreakHyphen: UTF8String; begin Result := U($2011); end;

// Appends bytes to bytes (never a conversion between code pages).
procedure Cat(var R: RawByteString; const S: RawByteString);
var
  n: Integer;
begin
  if S = '' then Exit;
  n := Length(R);
  SetLength(R, n + Length(S));
  Move(S[1], R[n + 1], Length(S));
end;

function Raw(const S: UTF8String): RawByteString;
begin
  Result := '';
  Cat(Result, S);
end;

function RepoRoot: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim;
end;

function FixtureDir: string;
begin
  Result := RepoRoot + 'tests' + PathDelim + 'fixtures' + PathDelim + 'rtf' + PathDelim;
end;

function ReadFileBytes(const APath: string): TBytes;
var
  f: TFileStream;
begin
  Result := nil;
  f := TFileStream.Create(APath, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, f.Size);
    if f.Size > 0 then f.ReadBuffer(Result[0], f.Size);
  finally
    f.Free;
  end;
end;

function BytesOf(const S: RawByteString): TBytes;
begin
  Result := nil;
  SetLength(Result, Length(S));
  if S <> '' then Move(S[1], Result[0], Length(S));
end;

function StrOf(const B: TBytes; AStart, ACount: Int64): RawByteString;
begin
  Result := '';
  if ACount <= 0 then Exit;
  SetLength(Result, ACount);
  Move(B[AStart], Result[1], ACount);
end;

function Shown(const S: RawByteString): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do
    if (S[i] >= ' ') and (S[i] < #$7F) then Result := Result + S[i]
    else Result := Result + '<' + IntToHex(Ord(S[i]), 2) + '>';
  if Length(Result) > 300 then Result := Copy(Result, 1, 300) + '...';
end;

function SameRaw(const A, B: RawByteString): Boolean;
begin
  Result := (Length(A) = Length(B)) and ((A = '') or CompareMem(@A[1], @B[1], Length(A)));
end;

procedure AssertRaw(const AMsg: string; const AExpected, AActual: RawByteString);
var
  i, from: Integer;
begin
  if SameRaw(AExpected, AActual) then Exit;
  // from a little before the first difference
  i := 1;
  while (i <= Length(AExpected)) and (i <= Length(AActual)) and (AExpected[i] = AActual[i]) do Inc(i);
  from := i - 30;
  if from < 1 then from := 1;
  raise EAssertionFailedError.CreateFmt('%s: at byte %d expected <%s> but was <%s>',
    [AMsg, i - 1, Shown(Copy(AExpected, from, 300)), Shown(Copy(AActual, from, 300))]);
end;

function PosRaw(const ASub, S: RawByteString; AFrom: Integer = 1): Integer;
var
  i: Integer;
begin
  for i := AFrom to Length(S) - Length(ASub) + 1 do
    if CompareMem(@S[i], @ASub[1], Length(ASub)) then Exit(i);
  Result := 0;
end;

function ParaText(ADoc: TTyRichDocument; AIndex: Integer): RawByteString;
begin
  Result := ADoc.Text.GetText(ADoc.Text.ParaStart(AIndex), ADoc.Text.ParaLength(AIndex));
  SetCodePage(Result, CP_NONE, False);
end;

function Utf8Chars(const S: RawByteString): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 1 to Length(S) do
    if Byte(S[i]) and $C0 <> $80 then Inc(Result);
end;

// The byte offset (0-based) of character AChar of S.
function CharOffset(const S: RawByteString; AChar: Integer): Integer;
begin
  Result := 0;
  while (Result < Length(S)) and (AChar > 0) do
  begin
    Inc(Result);
    while (Result < Length(S)) and (Byte(S[Result + 1]) and $C0 = $80) do Inc(Result);
    Dec(AChar);
  end;
end;

function LoadDoc(const ABytes: TBytes; AFull: Boolean): TTyRichDocument;
var
  s: TBytesStream;
begin
  Result := TTyRichDocument.Create;
  s := TBytesStream.Create(ABytes);
  try
    try
      if AFull then TyRichLoadRtfFull(Result, s) else TyRichLoadRtf(Result, s);
    except
      Result.Free;
      raise;
    end;
  finally
    s.Free;
  end;
end;

function SaveDoc(ADoc: TTyRichDocument; out AInfo: TTyRtfWriteInfo): TBytes;
var
  s: TBytesStream;
begin
  s := TBytesStream.Create;
  try
    TyRichSaveRtf(ADoc, s, AInfo);
    Result := Copy(s.Bytes, 0, s.Size);
  finally
    s.Free;
  end;
end;

function SaveBytes(ADoc: TTyRichDocument): TBytes;
var
  info: TTyRtfWriteInfo;
begin
  Result := SaveDoc(ADoc, info);
end;

function SameBytes(const A, B: TBytes): Boolean;
begin
  Result := (Length(A) = Length(B)) and ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A)));
end;

// Where two byte arrays first differ, with a little of both, for a failure message.
function FirstDiff(const A, B: TBytes): string;
var
  i, n: Integer;
begin
  n := Length(A);
  if Length(B) < n then n := Length(B);
  i := 0;
  while (i < n) and (A[i] = B[i]) do Inc(i);
  Result := Format('lengths %d and %d, first difference at %d: <%s> / <%s>', [Length(A),
    Length(B), i, Shown(StrOf(A, i, Length(A) - i)), Shown(StrOf(B, i, Length(B) - i))]);
  if Length(Result) > 400 then Result := Copy(Result, 1, 400);
end;

// How many groups are still open at the end of ABytes (braces that are escaped do not count).
function OpenGroups(const ABytes: TBytes): Integer;
var
  i: Integer;
begin
  Result := 0;
  i := 0;
  while i < Length(ABytes) do
  begin
    case ABytes[i] of
      Ord('\'): Inc(i);
      Ord('{'): Inc(Result);
      Ord('}'): Dec(Result);
    end;
    Inc(i);
  end;
end;

procedure SampleNames(AList: TStringList);
var
  sr: TSearchRec;
begin
  if FindFirst(FixtureDir + '*.rtf', faAnyFile, sr) = 0 then
  begin
    repeat
      AList.Add(sr.Name);
    until FindNext(sr) <> 0;
    FindClose(sr);
  end;
  AList.Sort;
end;

const
  // State that RTF carries from one paragraph to the next, each in a file small enough to
  // read: what the bytes after a rewritten paragraph depend on.
  InlineSources: array[0..7] of RawByteString = (
    // the font, the size and the paragraph properties are named once
    '{\rtf1\ansi\ansicpg936\deff0{\fonttbl{\f0\fnil\fcharset134 SimSun;}{\f1\fswiss\fcharset0 Arial;}}' +
      '{\colortbl ;\red255\green0\blue0;}\viewkind4\uc1 ' +
      '\pard\qc\li720\sb120\tqr\tx4000\f1\fs30\b\cf1 one\par two \''d6\''d0\par three\par' +
      '\pard\f0\fs20 four\par five\par}',
    // \uc2 from before the paragraphs: two fallback bytes after every \u
    '{\rtf1\ansi\ansicpg936\deff0{\fonttbl{\f0\fnil\fcharset134 SimSun;}}\uc2 ' +
      '\pard\f0\fs24 A \' + 'u20013\''d6\''d0\par B \' + 'u25991\''ce\''c4 b\par C \' +
      'u20013\''d6\''d0 c\par}',
    // Word's three font slots carried across paragraphs, each another font than the default
    // one; \hich was named last, so a quotation mark is in the high-ANSI font (after \dbch
    // it would be in the double-byte one)
    '{\rtf1\ansi\ansicpg936\deff0{\fonttbl{\f0\fswiss\fcharset0 Arial;}{\f1\fnil\fcharset134 SimSun;}' +
      '{\f2\froman\fcharset0 Times;}{\f3\fmodern\fcharset0 Courier;}}\uc1 ' +
      '\pard\fs24\loch\af2\dbch\af1\hich\af3 A\par B\' + 'u20013?b\' + 'u8220?\' + 'u233?\par C\' +
      'u25991?c\' + 'u8220?\' + 'u233?\par}',
    // unknown words in effect, on the run and on the paragraph, and \rtlch ... \ltrch
    '{\rtf1\ansi\ansicpg1252\deff0{\fonttbl{\f0\fswiss\fcharset0 Arial;}}\uc1 ' +
      '\pard\keepn\s3 \rtlch\fcs1 \af0 \ltrch\fcs0 \f0\fs24\lang2052\kerning2 A\par B\par ' +
      '\insrsid77 C\par}',
    // a group that spans paragraphs, and one that ends the body
    '{\rtf1\ansi\ansicpg1252\deff0{\fonttbl{\f0\fswiss\fcharset0 Arial;}{\f1\froman\fcharset0 Times;}}\uc1 ' +
      '\pard\f0\fs24 zero\par {\b\f1 A\par B\par} C\par D\par {\i E\par F\par}}',
    // a list whose later items inherit {\*\pn}, between plain paragraphs
    '{\rtf1\ansi\ansicpg1252\deff0{\fonttbl{\f0\fswiss\fcharset0 Arial;}{\f1\fnil\fcharset2 Symbol;}}\uc1 ' +
      '\pard\f0\fs24 before\par ' +
      '\pard{\pntext\f1\''B7\tab}{\*\pn\pnlvlblt\pnf1\pnindent0{\pntxtb\''B7}}\fi-360\li720 x\par ' +
      '{\pntext\f1\''B7\tab}y\par {\pntext\f1\''B7\tab}z\par \pard after\par}',
    // rows that take their definition from the row before, one with two paragraphs in a cell
    '{\rtf1\ansi\ansicpg1252\deff0{\fonttbl{\f0\fswiss\fcharset0 Arial;}}\uc1 ' +
      '\pard\f0\fs24 top\par \trowd\trgaph108\cellx2000\cellx4000 \pard\intbl a\cell b1\par b2\cell\row ' +
      '\trowd\trgaph108\cellx2000\cellx4000 \pard\intbl\b c\cell d\cell\row \pard\b0 bottom\par}',
    // no font table at all, and the last paragraph has no terminator
    '{\rtf1 A\par B\par C}'
  );

function InlineName(AIndex: Integer): string;
begin
  Result := 'inline ' + IntToStr(AIndex);
end;

function SameObject(A, B: TTyRichObject; ARaw: Boolean = True): Boolean;
var
  pa, pb: TTyRichPicture;
begin
  if (A = nil) or (B = nil) then Exit(A = B);
  if A.ClassType <> B.ClassType then Exit(False);
  if A is TTyRichOpaque then
    Exit(SameRaw(TTyRichOpaque(A).Bytes, TTyRichOpaque(B).Bytes) and
      SameRaw(TTyRichOpaque(A).DisplayText, TTyRichOpaque(B).DisplayText));
  pa := A as TTyRichPicture;
  pb := B as TTyRichPicture;
  Result := (pa.PictureFormat = pb.PictureFormat) and (pa.WidthTwips = pb.WidthTwips) and
    (pa.HeightTwips = pb.HeightTwips) and (not ARaw or SameRaw(pa.RawRtf, pb.RawRtf)) and
    (Length(pa.Data) = Length(pb.Data)) and
    ((Length(pa.Data) = 0) or CompareMem(@pa.Data[0], @pb.Data[0], Length(pa.Data)));
end;

function DescribeChar(const F: TTyCharFormat): string;
var
  i: Integer;
begin
  Result := Format('%s/%d %d st%d k%d v%d c%x h%x [', [Shown(F.FontName), F.Charset,
    F.SizeHalfPt, Integer(F.Style), Ord(F.Strike), Ord(F.VertAlign), F.Color, F.HighlightColor]);
  for i := 0 to F.Extra.Count - 1 do Result := Result + Shown(F.Extra.Item(i)) + '|';
  Result := Result + ']';
end;

function DescribePara(const F: TTyParaFormat): string;
var
  i: Integer;
begin
  Result := Format('a%d li%d ri%d fi%d sb%d sa%d ls%d/%d list%d/%d/%d rtl%d tabs', [Ord(F.Align),
    F.LeftIndent, F.RightIndent, F.FirstIndent, F.SpaceBefore, F.SpaceAfter, Ord(F.LineSpacing),
    F.LineSpacingValue, Ord(F.List.Kind), F.List.Level, F.List.StartAt, Ord(F.RtlPar)]);
  for i := 0 to High(F.Tabs) do
    Result := Result + Format(' %d/%d/%d', [F.Tabs[i].Position, Ord(F.Tabs[i].Align),
      Ord(F.Tabs[i].Leader)]);
  Result := Result + ' [';
  for i := 0 to F.Extra.Count - 1 do Result := Result + Shown(F.Extra.Item(i)) + '|';
  Result := Result + ']';
end;

// The table cell of paragraph AIndex as numbers: '' outside a table.
function DescribeCell(ADoc: TTyRichDocument; AIndex: Integer): string;
var
  c: TTyRichCell;
  k: Integer;
begin
  c := ADoc.CellAt(AIndex);
  if c = nil then Exit('');
  Result := Format('cell %d of %d, row %d of %d, locked %d, cols', [c.Index, c.Row.CellCount,
    c.Row.Index, c.Table.RowCount, Ord(c.Table.StructureLocked)]);
  for k := 0 to c.Table.ColBoundaryCount - 1 do
    Result := Result + ' ' + IntToStr(c.Table.ColBoundaries[k]);
  Result := Result + ' <' + Shown(c.Row.RawFormat) + '>';
end;

// '' when paragraph AI of A and paragraph BI of B are the same: text, paragraph format,
// runs (formats by value, objects by content) and table cell.
function ParaDiff(A: TTyRichDocument; AI: Integer; B: TTyRichDocument; BI: Integer): string;
var
  ra, rb: TTyRunArray;
  j: Integer;
  fa, fb: TTyCharFormat;
begin
  if not SameRaw(ParaText(A, AI), ParaText(B, BI)) then
    Exit(Format('text <%s> / <%s>', [Shown(ParaText(A, AI)), Shown(ParaText(B, BI))]));
  if not A.Formats.ParaFormat(A.ParaFormatOf(AI)).Equals(B.Formats.ParaFormat(B.ParaFormatOf(BI))) then
    Exit(Format('paragraph format %s / %s', [DescribePara(A.Formats.ParaFormat(A.ParaFormatOf(AI))),
      DescribePara(B.Formats.ParaFormat(B.ParaFormatOf(BI)))]));
  ra := A.RunsOf(AI);
  rb := B.RunsOf(BI);
  if Length(ra) <> Length(rb) then
    Exit(Format('%d runs / %d runs', [Length(ra), Length(rb)]));
  for j := 0 to High(ra) do
  begin
    if ra[j].Start <> rb[j].Start then
      Exit(Format('run %d starts at %d / %d', [j, ra[j].Start, rb[j].Start]));
    fa := A.Formats.CharFormat(ra[j].Format);
    fb := B.Formats.CharFormat(rb[j].Format);
    if not fa.Equals(fb) then
      Exit(Format('run %d format %s / %s', [j, DescribeChar(fa), DescribeChar(fb)]));
    if not SameObject(ra[j].Obj, rb[j].Obj) then Exit(Format('run %d object', [j]));
  end;
  if DescribeCell(A, AI) <> DescribeCell(B, BI) then
    Exit(Format('table: %s / %s', [DescribeCell(A, AI), DescribeCell(B, BI)]));
  Result := '';
end;

type
  TCharSpot = record
    Format: TTyCharFormat;
    Obj: TTyRichObject;
  end;
  TCharSpots = array of TCharSpot;

// The format (and object) of every character of a paragraph; an empty one has one entry.
function SpotsOf(ADoc: TTyRichDocument; AIndex: Integer): TCharSpots;
var
  runs: TTyRunArray;
  n, c, r: Integer;
begin
  runs := ADoc.RunsOf(AIndex);
  n := ADoc.Text.ParaLength(AIndex);
  Result := nil;
  if n = 0 then
  begin
    SetLength(Result, 1);
    Result[0].Format := ADoc.Formats.CharFormat(runs[0].Format);
    Result[0].Obj := nil;
    Exit;
  end;
  SetLength(Result, n);
  r := 0;
  for c := 0 to n - 1 do
  begin
    while (r < High(runs)) and (runs[r + 1].Start <= c) do Inc(r);
    Result[c].Format := ADoc.Formats.CharFormat(runs[r].Format);
    Result[c].Obj := runs[r].Obj;
  end;
end;

type
  // What a program adds itself: a table over existing paragraphs (the table commands come
  // with table editing).
  TMarkTableCommand = class(TTyRichCommand)
  private
    FFirst: Integer;
    FTable: TTyRichTable;
    FCells: array of Integer;
  protected
    procedure DoExecute(ADoc: TTyRichDocument); override;
  public
    constructor Create(AFirst: Integer; ATable: TTyRichTable; const ACells: array of Integer);
  end;

  // Compares what is written with the bytes it should be, without keeping it; counts the
  // writes and watches the heap while the writer works.
  TCheckStream = class(TStream)
  private
    FExpected: TBytes;
    FPos: Int64;
  public
    Writes: Integer;
    Mismatch: Int64;
    HeapBase, HeapPeak: Int64;
    constructor Create(const AExpected: TBytes);
    function Write(const Buffer; Count: LongInt): LongInt; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
    property Written: Int64 read FPos;
  end;

constructor TMarkTableCommand.Create(AFirst: Integer; ATable: TTyRichTable;
  const ACells: array of Integer);
var
  i: Integer;
begin
  inherited Create;
  FFirst := AFirst;
  FTable := ATable;
  SetLength(FCells, Length(ACells));
  for i := 0 to High(ACells) do FCells[i] := ACells[i];
end;

procedure TMarkTableCommand.DoExecute(ADoc: TTyRichDocument);
begin
  MarkTable(ADoc, FFirst, FTable, FCells);
end;

constructor TCheckStream.Create(const AExpected: TBytes);
begin
  inherited Create;
  FExpected := AExpected;
  Mismatch := -1;
  HeapBase := GetFPCHeapStatus.CurrHeapUsed;
  HeapPeak := HeapBase;
end;

function TCheckStream.Write(const Buffer; Count: LongInt): LongInt;
var
  used: Int64;
begin
  Inc(Writes);
  used := GetFPCHeapStatus.CurrHeapUsed;
  if used > HeapPeak then HeapPeak := used;
  if Mismatch < 0 then
    if (FPos + Count > Length(FExpected)) or
       ((Count > 0) and not CompareMem(@Buffer, @FExpected[FPos], Count)) then
      Mismatch := FPos;
  Inc(FPos, Count);
  Result := Count;
end;

function TCheckStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
begin
  Result := FPos;
end;

{ A sample's header, its body repeated until the file has at least ATarget bytes, and its
  trailer. }
function Generate(const ASample: string; ATarget: Int64): TBytes;
var
  b: TBytes;
  m: TTyRtfSourceMap;
  d: TTyRichDocument;
  s: TBytesStream;
  hs, bs, ts, len: Int64;
begin
  b := ReadFileBytes(FixtureDir + ASample);
  m := TTyRtfSourceMap.Create;
  d := TTyRichDocument.Create;
  s := TBytesStream.Create(b);
  try
    TyRichLoadRtfFull(d, s, m);
    hs := m.Header.Stop;
    bs := m.Trailer.Start - hs;
    ts := Length(b) - m.Trailer.Start;
  finally
    s.Free;
    d.Free;
    m.Free;
  end;
  Result := nil;
  SetLength(Result, ATarget + bs + ts + hs);
  Move(b[0], Result[0], hs);
  len := hs;
  while len + ts < ATarget do
  begin
    Move(b[hs], Result[len], bs);
    Inc(len, bs);
  end;
  Move(b[hs + bs], Result[len], ts);
  Inc(len, ts);
  SetLength(Result, len);
end;

function Fmt(const AName: string; ACharset, ASize: Integer): TTyCharFormat;
begin
  Result := TyDefaultCharFormat;
  Result.FontName := AName;
  Result.Charset := ACharset;
  Result.SizeHalfPt := ASize;
end;

const
  AllChar = [cffFontName, cffCharset, cffSize, cffBold, cffItalic, cffUnderline, cffStrike,
    cffVertAlign, cffColor, cffHighlight, cffExtra];
  AllPara = [pffAlign, pffLeftIndent, pffRightIndent, pffFirstIndent, pffSpaceBefore,
    pffSpaceAfter, pffLineSpacing, pffTabs, pffList, pffRtlPar, pffExtra];

procedure SetChars(ADoc: TTyRichDocument; APos, ALen: Int64; AMask: TTyCharFormatMask;
  const AValue: TTyCharFormat);
begin
  if not ADoc.Execute(TTyRichSetCharFormat.Create(TyRichRange(APos, ALen), AMask, AValue)) then
    raise Exception.Create('character format refused');
end;

procedure SetPara(ADoc: TTyRichDocument; AIndex: Integer; AMask: TTyParaFormatMask;
  const AValue: TTyParaFormat);
begin
  if not ADoc.Execute(TTyRichSetParaFormat.Create(AIndex, AIndex, AMask, AValue)) then
    raise Exception.Create('paragraph format refused');
end;

// A PNG's bytes: the picture of a sample (the system's RichEdit drops what it cannot decode).
function PngBytes: TBytes;
var
  d: TTyRichDocument;
  runs: TTyRunArray;
  i: Integer;
begin
  Result := nil;
  d := LoadDoc(ReadFileBytes(FixtureDir + 're-zh-picture.rtf'), True);
  try
    runs := d.RunsOf(1);
    for i := 0 to High(runs) do
      if runs[i].Obj is TTyRichPicture then
        Result := Copy(TTyRichPicture(runs[i].Obj).Data, 0, MaxInt);
  finally
    d.Free;
  end;
  if (Length(Result) < 8) or (Result[1] <> Ord('P')) then
    raise Exception.Create('re-zh-picture.rtf has no PNG in its second paragraph');
end;

{ The document of TestOwnFilesRoundTrip, made through commands only: every character and
  paragraph property of the model, lists, a picture, an unknown block, a table with a cell
  of two paragraphs. Every run names its font and size (a run in the theme's font has no
  name to write). }
function BuildOwnDocument: TTyRichDocument;
var
  d: TTyRichDocument;
  f: TTyCharFormat;
  p: TTyParaFormat;
  t: TTyRichTable;
  text: UTF8String;
  s: Int64;

  function Start(AIndex: Integer): Int64;
  begin
    Result := d.Text.ParaStart(AIndex);
  end;

begin
  d := TTyRichDocument.Create;
  Result := d;
  text :=
    'plain bold italic under strike up down red yellow big ' + ZhZhong + ZhWen + ' lang' + #10 +  // 0
    'tab' + #9 + 'line' + #11 + 'nbsp' + NoBreakSpace + 'nbhy' + NoBreakHyphen + ' \ { } ' + Grin + LeftQuote + EAcute + #10 +  // 1
    'centred' + #10 +                // 2
    'right exact' + #10 +            // 3
    'justified at least, tabs' + #10 +   // 4
    'one fifteen' + #10 +            // 5
    'double, kept with next' + #10 + // 6
    'bullet a' + #10 + 'bullet b' + #10 + 'bullet c' + #10 +   // 7 8 9
    'third' + #10 + 'fourth' + #10 +     // 10 11
    'roman' + #10 +                  // 12
    'picture  and block  here' + #10 +   // 13
    'r0c0' + #10 + 'r0c1 first' + #10 + 'r0c1 second' + #10 + 'r1c0' + #10 + 'r1c1' + #10 +   // 14..18
    '' + #10 +                       // 19: empty
    'the end';                       // 20
  d.Execute(TTyRichInsertText.Create(0, text));
  SetChars(d, 0, d.Text.Length, AllChar, Fmt('Arial', 0, 24));
  // paragraph 0: one property per word
  s := Start(0);
  f := TyDefaultCharFormat;
  f.Style := [fsBold];
  SetChars(d, s + 6, 4, [cffBold], f);
  f.Style := [fsItalic];
  SetChars(d, s + 11, 6, [cffItalic], f);
  f.Style := [fsUnderline];
  SetChars(d, s + 18, 5, [cffUnderline], f);
  f.Strike := True;
  SetChars(d, s + 24, 6, [cffStrike], f);
  f.VertAlign := vaSuper;
  SetChars(d, s + 31, 2, [cffVertAlign], f);
  f.VertAlign := vaSub;
  SetChars(d, s + 34, 4, [cffVertAlign], f);
  f.Color := RGBToColor(255, 0, 0);
  SetChars(d, s + 39, 3, [cffColor], f);
  f.HighlightColor := RGBToColor(255, 255, 0);
  SetChars(d, s + 43, 6, [cffHighlight], f);
  f.SizeHalfPt := 36;
  SetChars(d, s + 50, 3, [cffSize], f);
  SetChars(d, s + 54, 2, [cffFontName, cffCharset], Fmt(ZhSongTi, 134, 24));
  f := TyDefaultCharFormat;
  f.Extra.Add('\lang2052');
  f.Extra.Add('\kerning2 ');
  SetChars(d, s + 57, 4, [cffExtra], f);
  // paragraphs
  p := TyDefaultParaFormat;
  p.Align := paraCenter;
  p.LeftIndent := 720;
  p.RightIndent := 360;
  p.FirstIndent := -360;
  p.SpaceBefore := 240;
  p.SpaceAfter := 120;
  p.LineSpacing := ls15;
  SetPara(d, 2, AllPara, p);
  p := TyDefaultParaFormat;
  p.Align := paraRight;
  p.LineSpacing := lsExact;
  p.LineSpacingValue := 400;
  SetPara(d, 3, AllPara, p);
  p := TyDefaultParaFormat;
  p.Align := paraJustify;
  p.LineSpacing := lsAtLeast;
  p.LineSpacingValue := 300;
  p.RtlPar := True;
  SetLength(p.Tabs, 4);
  p.Tabs[0].Position := 1440;
  p.Tabs[1].Position := 4320;
  p.Tabs[1].Align := ttaCenter;
  p.Tabs[1].Leader := ttlDot;
  p.Tabs[2].Position := 8640;
  p.Tabs[2].Align := ttaRight;
  p.Tabs[2].Leader := ttlUnderline;
  p.Tabs[3].Position := 9000;
  p.Tabs[3].Align := ttaDecimal;
  p.Tabs[3].Leader := ttlHyphen;
  SetPara(d, 4, AllPara, p);
  p := TyDefaultParaFormat;
  p.LineSpacing := ls115;
  SetPara(d, 5, AllPara, p);
  p := TyDefaultParaFormat;
  p.LineSpacing := lsDouble;
  p.Extra.Add('\keepn');
  SetPara(d, 6, AllPara, p);
  p := TyDefaultParaFormat;
  p.List.Kind := lkBullet;
  p.FirstIndent := -360;
  p.LeftIndent := 720;
  d.Execute(TTyRichSetParaFormat.Create(7, 9, AllPara, p));
  p.List.Kind := lkDecimal;
  p.List.StartAt := 3;
  d.Execute(TTyRichSetParaFormat.Create(10, 11, AllPara, p));
  p.List.Kind := lkUpperRoman;
  p.List.Level := 1;
  p.List.StartAt := 1;
  SetPara(d, 12, AllPara, p);
  // a picture and an unknown block, each in the place of one of the two spaces
  s := Start(13);
  d.Execute(TTyRichDelete.Create(s + 8, 1));
  d.Execute(TTyRichInsertObject.Create(s + 8, TTyRichPicture.Create(rpfPng, PngBytes, 720, 480)));
  d.Execute(TTyRichDelete.Create(s + 19, 1));
  d.Execute(TTyRichInsertObject.Create(s + 19, TTyRichOpaque.Create('{\*\tyunknown some {nested} thing}')));
  // a table: two rows of two cells, the second cell of the first row with two paragraphs
  t := TTyRichTable.Create([2400, 4800]);
  t.AddRow(2);
  t.AddRow(2);
  d.Execute(TMarkTableCommand.Create(14, t, [1, 2, 1, 1]));
  f := TyDefaultCharFormat;
  f.Style := [fsBold];
  SetChars(d, Start(16), 4, [cffBold], f);
end;

{ ---- the brief ---- }

procedure TTyRtfWriteTest.TestOpenSaveIsByteIdentical;
var
  names: TStringList;
  i, j, parses: Integer;
  b, o: TBytes;
  d: TTyRichDocument;
  info: TTyRtfWriteInfo;
  load: TTyRtfLoad;
  msg: string;
begin
  names := TStringList.Create;
  try
    SampleNames(names);
    AssertTrue('the samples are there', names.Count >= 21);
    for i := 0 to names.Count + High(InlineSources) do
    begin
      if i < names.Count then
      begin
        msg := names[i];
        b := ReadFileBytes(FixtureDir + names[i]);
      end
      else
      begin
        msg := InlineName(i - names.Count);
        b := BytesOf(InlineSources[i - names.Count]);
      end;
      // saved straight after loading: nothing is parsed
      d := LoadDoc(b, False);
      try
        load := TyRichRtfLoadOf(d);
        parses := load.ParseCount;
        o := SaveDoc(d, info);
        AssertTrue(msg + ': unread, ' + FirstDiff(b, o), SameBytes(b, o));
        AssertEquals(msg + ': unread, nothing rewritten', 0, Length(info.Stretches));
        AssertEquals(msg + ': unread, every paragraph copied', d.Text.ParaCount, info.VerbatimParas);
        AssertEquals(msg + ': unread, nothing parsed to save', parses, load.ParseCount);
        AssertFalse(msg + ': saving is no change', d.Modified);
        // and with every paragraph parsed (its formats set, its text decoded): the bytes
        // still come from the file, not from the model
        for j := 0 to d.Text.ParaCount - 1 do
        begin
          d.EnsureParsed(j);
          ParaText(d, j);
        end;
        o := SaveDoc(d, info);
        AssertTrue(msg + ': parsed, ' + FirstDiff(b, o), SameBytes(b, o));
        AssertEquals(msg + ': parsed, nothing rewritten', 0, Length(info.Stretches));
      finally
        d.Free;
      end;
    end;
  finally
    names.Free;
  end;
end;

procedure TTyRtfWriteTest.TestOwnFilesRoundTrip;
var
  d, r: TTyRichDocument;
  o, o2: TBytes;
  info: TTyRtfWriteInfo;
  i, j: Integer;
  pd, pr: TTyParaFormat;
  rd, rr: TTyRunArray;
  msg: string;
  cd, cr: TTyRichCell;
  text: RawByteString;
begin
  d := BuildOwnDocument;
  r := nil;
  try
    o := SaveDoc(d, info);
    text := StrOf(o, 0, Length(o));
    AssertEquals('one stretch: the whole document', 1, Length(info.Stretches));
    AssertEquals('all of it from the model', d.Text.ParaCount, info.RewrittenParas);
    AssertTrue('WordPad''s header: ' + Shown(text),
      PosRaw('{\rtf1\ansi\ansicpg936\deff0\nouicompat{\fonttbl{\f1\fnil\fcharset0 Arial;}', text) = 1);
    AssertTrue('ends with } CR LF', SameRaw(StrOf(o, Length(o) - 3, 3), '}' + #13#10));
    r := LoadDoc(o, True);
    AssertEquals('paragraphs', d.Text.ParaCount, r.Text.ParaCount);
    for i := 0 to d.Text.ParaCount - 1 do
    begin
      msg := Format('paragraph %d', [i]);
      AssertRaw(msg + ' text', ParaText(d, i), ParaText(r, i));
      pd := d.Formats.ParaFormat(d.ParaFormatOf(i));
      pr := r.Formats.ParaFormat(r.ParaFormatOf(i));
      if pd.List.Kind <> lkNone then
      begin
        // a list made by a command is written as RichEdit writes one, and the words of
        // {\*\pn} the model has no field for come back as Extra
        AssertEquals(msg + ' the list''s own words: ' + DescribePara(pr), 3, pr.Extra.Count);
        AssertTrue(msg + ' \pnf', Copy(pr.Extra.Item(0), 1, 4) = '\pnf');
        AssertRaw(msg + ' \pnindent', '\pnindent0', pr.Extra.Item(1));
        if pd.List.Kind = lkBullet then AssertRaw(msg + ' bullet', '{\pntxtb\''B7}', pr.Extra.Item(2))
        else AssertRaw(msg + ' number', '{\pntxta.}', pr.Extra.Item(2));
        pr.Extra.Clear;
      end;
      AssertTrue(Format('%s paragraph format %s / %s', [msg, DescribePara(pd), DescribePara(pr)]),
        pd.Equals(pr));
      rd := d.RunsOf(i);
      rr := r.RunsOf(i);
      AssertEquals(msg + ' runs', Length(rd), Length(rr));
      for j := 0 to High(rd) do
      begin
        AssertEquals(Format('%s run %d start', [msg, j]), rd[j].Start, rr[j].Start);
        AssertTrue(Format('%s run %d format %s / %s', [msg, j,
          DescribeChar(d.Formats.CharFormat(rd[j].Format)), DescribeChar(r.Formats.CharFormat(rr[j].Format))]),
          d.Formats.CharFormat(rd[j].Format).Equals(r.Formats.CharFormat(rr[j].Format)));
        // (a picture read from a file has the bytes of its group; one made here has none)
        AssertTrue(Format('%s run %d object', [msg, j]), SameObject(rd[j].Obj, rr[j].Obj, False));
      end;
      cd := d.CellAt(i);
      cr := r.CellAt(i);
      AssertEquals(msg + ' in a table', cd <> nil, cr <> nil);
      if cd <> nil then
      begin
        AssertEquals(msg + ' cell', cd.Index, cr.Index);
        AssertEquals(msg + ' row', cd.Row.Index, cr.Row.Index);
        AssertEquals(msg + ' cells', cd.Row.CellCount, cr.Row.CellCount);
        AssertEquals(msg + ' rows', cd.Table.RowCount, cr.Table.RowCount);
        AssertEquals(msg + ' columns', cd.Table.ColBoundaryCount, cr.Table.ColBoundaryCount);
        for j := 0 to cd.Table.ColBoundaryCount - 1 do
          AssertEquals(msg + ' column', cd.Table.ColBoundaries[j], cr.Table.ColBoundaries[j]);
        AssertFalse(msg + ' not locked', cr.Table.StructureLocked);
        AssertRaw(msg + ' row format', '\trowd\trgaph108\cellx2400\cellx4800', cr.Row.RawFormat);
      end;
    end;
    AssertTrue('one table', r.CellAt(14).Table = r.CellAt(18).Table);
    // a file we wrote is a file we can open and save unchanged
    r.Free;
    r := LoadDoc(o, False);
    o2 := SaveBytes(r);
    AssertTrue('saved again: ' + FirstDiff(o, o2), SameBytes(o, o2));
  finally
    r.Free;
    d.Free;
  end;
end;

procedure TTyRtfWriteTest.TestChineseIsWrittenAsUnicodeEscapes;
var
  d, r: TTyRichDocument;
  o: TBytes;
  text: RawByteString;
  i: Integer;
  info: TTyRtfWriteInfo;
  f: TTyCharFormat;
  b: TBytes;
begin
  // a document of our own: Chinese in a font that names no charset
  d := TTyRichDocument.Create;
  r := nil;
  try
    d.Execute(TTyRichInsertText.Create(0, ZhZhong + ZhWen + ' abc ' + Grin + LeftQuote + 'q' +
      EAcute + #10 + 'kana ' + KanaA + #10 + 'hangul ' + HangulHan + #10 + 'latin only'));
    SetChars(d, 0, d.Text.ParaLength(0), [cffFontName, cffSize], Fmt(ZhSongTi, DEFAULT_CHARSET, 24));
    SetChars(d, d.Text.ParaStart(1), d.Text.ParaLength(1), [cffFontName, cffSize], Fmt('Meiryo', DEFAULT_CHARSET, 24));
    SetChars(d, d.Text.ParaStart(2), d.Text.ParaLength(2), [cffFontName, cffSize], Fmt('Gulim', DEFAULT_CHARSET, 24));
    SetChars(d, d.Text.ParaStart(3), d.Text.ParaLength(3), [cffFontName, cffSize], Fmt('Verdana', DEFAULT_CHARSET, 24));
    o := SaveBytes(d);
    text := StrOf(o, 0, Length(o));
    for i := 0 to High(o) do
      if o[i] > $7F then Fail(Format('byte %d of the output is %x: %s', [i, o[i], Shown(text)]));
    // the Chinese font's entry: \fcharset134, its name in the code page's bytes
    AssertTrue('the Chinese font: ' + Shown(text),
      PosRaw('\fnil\fcharset134 \''cb\''ce\''cc\''e5;}', text) > 0);
    AssertTrue('kana: Japanese: ' + Shown(text), PosRaw('\fnil\fcharset128 Meiryo;}', text) > 0);
    AssertTrue('Hangul: Korean: ' + Shown(text), PosRaw('\fnil\fcharset129 Gulim;}', text) > 0);
    AssertTrue('Latin: ANSI: ' + Shown(text), PosRaw('\fnil\fcharset0 Verdana;}', text) > 0);
    AssertTrue('the code page is the Chinese one: ' + Shown(text), PosRaw('\ansicpg936', text) > 0);
    AssertTrue('one fallback character: ' + Shown(text), PosRaw('\uc1 ', text) > 0);
    AssertTrue('every character as \uN?: ' + Shown(text),
      PosRaw(BS + 'u20013?' + BS + 'u25991? abc ' + BS + 'u-10179?' + BS + 'u-8704?' + BS +
        'u8220?q' + BS + 'u233?', text) > 0);
    r := LoadDoc(o, True);
    AssertEquals('read back: paragraphs', 4, r.Text.ParaCount);
    for i := 0 to 3 do AssertRaw(Format('read back: paragraph %d', [i]), ParaText(d, i), ParaText(r, i));
    f := r.Formats.CharFormat(r.RunsOf(0)[0].Format);
    AssertEquals('read back: the font', ZhSongTi, f.FontName);
    AssertEquals('read back: its charset', 134, f.Charset);
  finally
    r.Free;
    d.Free;
  end;
  // a paragraph of a Chinese file rewritten: its bytes are ASCII too (the rest is the file's)
  b := ReadFileBytes(FixtureDir + 'wp-zh-mixed.rtf');
  d := LoadDoc(b, False);
  try
    d.Execute(TTyRichInsertText.Create(d.Text.ParaStart(2) + 3, ZhZhong));
    o := SaveDoc(d, info);
    AssertEquals('one stretch', 1, Length(info.Stretches));
    for i := Integer(info.Stretches[0].OutStart) to Integer(info.Stretches[0].OutStop) - 1 do
      if o[i] > $7F then Fail(Format('byte %d of the rewritten paragraph is %x', [i, o[i]]));
    AssertTrue('the typed character as \uN?', PosRaw(BS + 'u20013?',
      StrOf(o, info.Stretches[0].OutStart, info.Stretches[0].OutStop - info.Stretches[0].OutStart)) > 0);
  finally
    d.Free;
  end;
end;

procedure TTyRtfWriteTest.TestAnEditAtTheEndOfALazyDocumentRewritesOnlyThatParagraph;
var
  b, o: TBytes;
  d, r: TTyRichDocument;
  load: TTyRtfLoad;
  last: Integer;
  parsed, lastStart: Int64;
  range: TTyRtfRange;
  info: TTyRtfWriteInfo;
  before: RawByteString;
begin
  b := Generate('re-zh-mixed.rtf', 5 * MB);
  d := LoadDoc(b, False);
  r := nil;
  try
    load := TyRichRtfLoadOf(d);
    last := d.Text.ParaCount - 1;
    AssertTrue('the last paragraph is the file''s', load.ParaSource(last, range));
    lastStart := range.Start;
    before := ParaText(d, last);
    AssertTrue('typed at the end', d.Execute(TTyRichInsertText.Create(d.Text.Length, 'X')));
    parsed := load.ParsedBytes;
    o := SaveDoc(d, info);
    AssertEquals('nothing parsed to save', parsed, load.ParsedBytes);
    AssertEquals('one stretch', 1, Length(info.Stretches));
    AssertEquals('the last paragraph', last, info.Stretches[0].FirstPara);
    AssertEquals('alone', 1, info.Stretches[0].ParaCount);
    AssertEquals('every other paragraph copied', last, info.VerbatimParas);
    // the file up to the last paragraph, the paragraph from the model, the file's trailer
    AssertEquals('it starts where it started in the file', lastStart, info.Stretches[0].OutStart);
    AssertTrue('the file''s bytes before it', CompareMem(@o[0], @b[0], lastStart));
    AssertEquals('the trailer follows it', info.Stretches[0].OutStop, info.TrailerStart);
    AssertRaw('the trailer', StrOf(b, load.Trailer.Start, Length(b) - load.Trailer.Start),
      StrOf(o, info.TrailerStart, Length(o) - info.TrailerStart));
    AssertTrue('the paragraph is a few hundred bytes', info.Stretches[0].OutStop - info.Stretches[0].OutStart < 2000);
    r := LoadDoc(o, False);
    AssertEquals('read back: paragraphs', d.Text.ParaCount, r.Text.ParaCount);
    Cat(before, 'X');
    AssertRaw('read back: the last paragraph', before, ParaText(r, last));
    AssertEquals('read back: its runs and formats', '', ParaDiff(d, last, r, last));
    AssertEquals('read back: the one before it', '', ParaDiff(d, last - 1, r, last - 1));
  finally
    r.Free;
    d.Free;
  end;
end;

{ ---- the system's RichEdit ---- }

{$IFDEF WINDOWS}
type
  // richedit.h declares its structures under #pragma pack(4), on Win64 too
  {$PUSH}{$PACKRECORDS 4}
  TReEditStream = record
    dwCookie: PtrUInt;
    dwError: DWORD;
    pfnCallback: Pointer;
  end;
  TReGetTextEx = record
    cb: DWORD;
    flags: DWORD;
    codepage: UINT;
    lpDefaultChar: PAnsiChar;
    lpUsedDefChar: Pointer;
  end;
  TReGetTextLengthEx = record
    flags: DWORD;
    codepage: UINT;
  end;
  {$POP}

  TReSource = record
    Data: PByte;
    Left: Int64;
  end;
  PReSource = ^TReSource;

const
  ReEmExLimitText = WM_USER + 53;
  ReEmStreamIn = WM_USER + 73;
  ReEmGetTextEx = WM_USER + 94;
  ReEmGetTextLengthEx = WM_USER + 95;
  ReSfRtf = 2;
  ReGtRawText = 4;

function ReStreamIn(dwCookie: PtrUInt; pbBuff: PByte; cb: LongInt; pcb: PLongInt): DWORD; stdcall;
var
  src: PReSource;
  n: LongInt;
begin
  src := PReSource(dwCookie);
  n := cb;
  if n > src^.Left then n := src^.Left;
  if n > 0 then Move(src^.Data^, pbBuff^, n);
  Inc(src^.Data, n);
  Dec(src^.Left, n);
  pcb^ := n;
  Result := 0;
end;

// The text the system's RichEdit holds after reading ARtf, as UTF-8 (objects U+FFFC, the
// table marks as they are). False: msftedit.dll or its window class is not there.
function RichEditText(const ARtf: TBytes; out AText: RawByteString): Boolean;
var
  h: HWND;
  es: TReEditStream;
  src: TReSource;
  gl: TReGetTextLengthEx;
  gt: TReGetTextEx;
  n, got: PtrInt;
  buf: UnicodeString;
  u8: UTF8String;
begin
  AText := '';
  if LoadLibraryW('msftedit.dll') = 0 then Exit(False);
  // a message-only window: nothing is shown, the clipboard and the focus are not touched
  h := CreateWindowExW(0, 'RICHEDIT50W', '', ES_MULTILINE, 0, 0, 800, 600, HWND(PtrInt(-3)), 0,
    HInstance, nil);
  if h = 0 then Exit(False);
  try
    SendMessageW(h, ReEmExLimitText, 0, $7FFFFFF);
    src.Data := nil;
    if Length(ARtf) > 0 then src.Data := @ARtf[0];
    src.Left := Length(ARtf);
    es.dwCookie := PtrUInt(@src);
    es.dwError := 0;
    es.pfnCallback := @ReStreamIn;
    SendMessageW(h, ReEmStreamIn, ReSfRtf, LPARAM(@es));
    gl.flags := 0;
    gl.codepage := 1200;
    n := SendMessageW(h, ReEmGetTextLengthEx, WPARAM(@gl), 0);
    buf := '';
    SetLength(buf, n + 1);
    gt.cb := (n + 1) * 2;
    gt.flags := ReGtRawText;
    gt.codepage := 1200;
    gt.lpDefaultChar := nil;
    gt.lpUsedDefChar := nil;
    got := SendMessageW(h, ReEmGetTextEx, WPARAM(@gt), LPARAM(PWideChar(buf)));
    SetLength(buf, got);
    u8 := UTF8Encode(buf);
    AText := u8;
    SetCodePage(AText, CP_NONE, False);
    Result := True;
  finally
    DestroyWindow(h);
  end;
end;

// The model's text as that control reports a document: CR after a paragraph (none after the
// last), in a table U+FFF9 CR before a row, U+0007 after a cell, U+FFFB CR after a row; a
// picture is U+FFFC, a block the control does not know is nothing.
function ModelAsRichEditText(ADoc: TTyRichDocument): RawByteString;
var
  rowStart, rowEnd: RawByteString;
  i, j, last: Integer;
  runs: TTyRunArray;
  text, part: RawByteString;
  cell, next, prev: TTyRichCell;
  from, upto: Integer;
begin
  Result := '';
  rowStart := Raw(U($FFF9) + #13);
  rowEnd := Raw(U($FFFB) + #13);
  last := ADoc.Text.ParaCount - 1;
  prev := nil;
  for i := 0 to last do
  begin
    cell := ADoc.CellAt(i);
    if i < last then next := ADoc.CellAt(i + 1) else next := nil;
    if (cell <> nil) and ((prev = nil) or (prev.Row <> cell.Row)) then Cat(Result, rowStart);
    text := ParaText(ADoc, i);
    runs := ADoc.RunsOf(i);
    for j := 0 to High(runs) do
    begin
      from := CharOffset(text, runs[j].Start);
      if j < High(runs) then upto := CharOffset(text, runs[j + 1].Start) else upto := Length(text);
      part := Copy(text, from + 1, upto - from);
      if runs[j].Obj is TTyRichOpaque then part := '';
      Cat(Result, part);
    end;
    if cell = nil then
    begin
      if i < last then Cat(Result, #13);
    end
    else if next = cell then
      Cat(Result, #13)
    else
    begin
      Cat(Result, #7);
      if (next = nil) or (next.Row <> cell.Row) then Cat(Result, rowEnd);
    end;
    prev := cell;
  end;
end;

// The control's text as paragraphs: a cell end ends a paragraph, the row marks and the
// marks of swallowed cells are dropped.
function AsParagraphs(const AText: RawByteString): RawByteString;
var
  i, n: Integer;
begin
  Result := '';
  n := Length(AText);
  i := 1;
  while i <= n do
  begin
    // U+FFF9 CR and U+FFFB CR: EF BF B9 0D, EF BF BB 0D
    if (i + 3 <= n) and (AText[i] = #$EF) and (AText[i + 1] = #$BF) and
       (AText[i + 2] in [#$B9, #$BB]) and (AText[i + 3] = #13) then
      Inc(i, 4)
    // U+FFFF: what the control puts in a cell that a merged one swallowed
    else if (i + 2 <= n) and (AText[i] = #$EF) and (AText[i + 1] = #$BF) and (AText[i + 2] = #$BF) then
      Inc(i, 3)
    else
    begin
      if AText[i] = #7 then Cat(Result, #13) else Cat(Result, AText[i]);
      Inc(i);
    end;
  end;
end;

type
  TRawArray = array of RawByteString;

function SplitParas(const AText: RawByteString): TRawArray;
var
  i, from, n: Integer;
begin
  Result := nil;
  n := 0;
  from := 1;
  for i := 1 to Length(AText) + 1 do
    if (i > Length(AText)) or (AText[i] = #13) then
    begin
      SetLength(Result, n + 1);
      Result[n] := Copy(AText, from, i - from);
      Inc(n);
      from := i + 1;
    end;
end;
{$ENDIF}

procedure TTyRtfWriteTest.CheckRichEditReads(const AMsg: string; ADoc: TTyRichDocument);
{$IFDEF WINDOWS}
var
  o: TBytes;
  got: RawByteString;
begin
  o := SaveBytes(ADoc);
  AssertTrue(AMsg + ': the control read it', RichEditText(o, got));
  AssertRaw(AMsg + ': the control''s text', ModelAsRichEditText(ADoc), got);
end;
{$ELSE}
begin
end;
{$ENDIF}

procedure TTyRtfWriteTest.TestWindowsRichEditReadsWhatWeWrite;
{$IFDEF WINDOWS}
var
  d: TTyRichDocument;
  names: TStringList;
  i, j, k, n, step: Integer;
  b, o: TBytes;
  original, got: RawByteString;
  gotParas, origParas, modelParas: TRawArray;
  p: TTyParaFormat;
  info: TTyRtfWriteInfo;
  objects: Boolean;
begin
  if not RichEditText(BytesOf('{\rtf1 x\par}'), got) then
  begin
    Ignore('msftedit.dll (the system''s RichEdit) cannot be loaded here');
    Exit;
  end;
  AssertRaw('the control reads', 'x', got);
  // a document of our own, with everything in it
  d := BuildOwnDocument;
  try
    CheckRichEditReads('own document', d);
  finally
    d.Free;
  end;
  // every sample with one paragraph rewritten (a paragraph format set: its row, in a table)
  names := TStringList.Create;
  try
    SampleNames(names);
    for i := 0 to names.Count - 1 do
    begin
      // (made to show where the control misreads a double-byte character split by a brace:
      // what it reads of the file's own paragraphs depends on which of them was rewritten)
      if names[i] = 'hand-split-dbcs.rtf' then Continue;
      b := ReadFileBytes(FixtureDir + names[i]);
      AssertTrue(names[i] + ': the control reads the sample', RichEditText(b, original));
      d := LoadDoc(b, False);
      try
        n := d.Text.ParaCount;
      finally
        d.Free;
      end;
      step := 1;
      if n > 14 then step := n div 14 + 1;
      k := 0;
      while k < n do
      begin
        d := LoadDoc(b, False);
        try
          p := TyDefaultParaFormat;
          p.RightIndent := 77;
          SetPara(d, k, [pffRightIndent], p);
          o := SaveDoc(d, info);
          AssertTrue(Format('%s paragraph %d: something was rewritten', [names[i], k]),
            info.RewrittenParas >= 1);
          AssertTrue(Format('%s paragraph %d: the control read it', [names[i], k]), RichEditText(o, got));
          // paragraph by paragraph (a cell end ends one; a row written from the model has
          // no nested table, but its cells' paragraphs are all there): a rewritten one is
          // the model's text, the others are what the control makes of the sample itself
          gotParas := SplitParas(AsParagraphs(got));
          origParas := SplitParas(AsParagraphs(original));
          modelParas := SplitParas(AsParagraphs(ModelAsRichEditText(d)));
          AssertEquals(Format('%s paragraph %d: the control''s paragraphs', [names[i], k]),
            d.Text.ParaCount, Length(gotParas));
          // the model cannot say what the control shows for a field, a footnote or a
          // formula, and the control does not load WordPad's metafiles without a window
          objects := (Pos('word-unknown', names[i]) > 0) or (Pos('wp-zh-picture', names[i]) > 0);
          for j := 0 to High(gotParas) do
            if not objects and (j >= info.Stretches[0].FirstPara) and
               (j < info.Stretches[0].FirstPara + info.Stretches[0].ParaCount) then
              AssertRaw(Format('%s paragraph %d rewritten: paragraph %d is the model''s text',
                [names[i], k, j]), modelParas[j], gotParas[j])
            else
              AssertRaw(Format('%s paragraph %d rewritten: paragraph %d is as the control reads the sample',
                [names[i], k, j]), origParas[j], gotParas[j]);
        finally
          d.Free;
        end;
        Inc(k, step);
      end;
    end;
  finally
    names.Free;
  end;
end;
{$ELSE}
begin
  Ignore('needs the system''s RichEdit (msftedit.dll): Windows only');
end;
{$ENDIF}

{ ---- the rulings ---- }

{ Where every paragraph that was not rewritten is in the output: the file's own bytes, one
  after the other, with the stretches between them; then the file's trailer. }
procedure TTyRtfWriteTest.CheckVerbatim(const AMsg: string; ADoc: TTyRichDocument;
  const ABytes, AOut: TBytes; const AInfo: TTyRtfWriteInfo);
var
  load: TTyRtfLoad;
  j, s, n: Integer;
  cursor: Int64;
  r: TTyRtfRange;
begin
  load := TyRichRtfLoadOf(ADoc);
  n := ADoc.Text.ParaCount;
  cursor := AInfo.HeaderStop;
  s := 0;
  j := 0;
  while j <= n do
  begin
    if (s < Length(AInfo.Stretches)) and (AInfo.Stretches[s].FirstPara = j) then
    begin
      AssertEquals(Format('%s: stretch %d starts where the bytes before it end', [AMsg, s]),
        cursor, AInfo.Stretches[s].OutStart);
      cursor := AInfo.Stretches[s].OutStop;
      Inc(j, AInfo.Stretches[s].ParaCount);
      Inc(s);
      Continue;
    end;
    if j = n then Break;
    AssertTrue(Format('%s: paragraph %d outside the stretches is the file''s own', [AMsg, j]),
      load.ParaSource(j, r));
    AssertTrue(Format('%s: paragraph %d fits', [AMsg, j]), cursor + (r.Stop - r.Start) <= Length(AOut));
    AssertRaw(Format('%s: paragraph %d is in the output as it is in the file', [AMsg, j]),
      StrOf(ABytes, r.Start, r.Stop - r.Start), StrOf(AOut, cursor, r.Stop - r.Start));
    Inc(cursor, r.Stop - r.Start);
    Inc(j);
  end;
  AssertEquals(AMsg + ': every stretch placed', Length(AInfo.Stretches), s);
  AssertEquals(AMsg + ': the trailer follows', cursor, AInfo.TrailerStart);
  AssertRaw(AMsg + ': the trailer', StrOf(ABytes, load.Trailer.Start, Length(ABytes) - load.Trailer.Start),
    StrOf(AOut, AInfo.TrailerStart, Length(AOut) - AInfo.TrailerStart));
  AssertRaw(AMsg + ': the header', StrOf(ABytes, 0, load.Header.Stop), StrOf(AOut, 0, AInfo.HeaderStop));
end;

{ Changes paragraph APara of the file ABytes (AFull: its full parse), saves, parses the
  result in full and compares: the paragraph has the change and nothing else, every other
  paragraph is what it was. }
procedure TTyRtfWriteTest.CheckEdit(const AName: string; const ABytes: TBytes;
  AFull: TTyRichDocument; APara: Integer; AKind: TEditKind);
const
  KindName: array[TEditKind] of string = ('insert', 'character format', 'paragraph format',
    'delete');
var
  d, w, w2: TTyRichDocument;
  o, o2: TBytes;
  info: TTyRtfWriteInfo;
  msg, diff: string;
  n, len, mid, i, shift, c: Integer;
  start: Int64;
  f, e: TTyCharFormat;
  p, pe: TTyParaFormat;
  so, sw: TCharSpots;
  expected, tail: RawByteString;
  changed: Boolean;
begin
  msg := Format('%s, paragraph %d, %s', [AName, APara, KindName[AKind]]);
  n := AFull.Text.ParaCount;
  len := AFull.Text.ParaLength(APara);
  mid := len div 2;
  d := LoadDoc(ABytes, False);
  w := nil;
  w2 := nil;
  try
    start := d.Text.ParaStart(APara);
    changed := True;
    case AKind of
      ekInsert:
        changed := d.Execute(TTyRichInsertText.Create(start + mid, 'X'));
      ekCharFormat:
        begin
          f := TyDefaultCharFormat;
          f.Style := [fsUnderline];
          if len > 0 then
          begin
            if mid = 0 then mid := 1;
            changed := d.Execute(TTyRichSetCharFormat.Create(TyRichRange(start, mid), [cffUnderline], f));
          end
          else if APara < n - 1 then
            // an empty paragraph: its separator, which changes its one run
            changed := d.Execute(TTyRichSetCharFormat.Create(TyRichRange(start, 1), [cffUnderline], f))
          else
            changed := False;
        end;
      ekParaFormat:
        begin
          p := TyDefaultParaFormat;
          p.SpaceBefore := 77;
          changed := d.Execute(TTyRichSetParaFormat.Create(APara, APara, [pffSpaceBefore], p));
        end;
      ekDelete:
        changed := d.Execute(TTyRichDelete.Create(start, len + 1));
    end;
    o := SaveDoc(d, info);
    if not changed then
    begin
      AssertTrue(msg + ': nothing changed, ' + FirstDiff(ABytes, o), SameBytes(ABytes, o));
      Exit;
    end;
    // what was not rewritten is the file's, where it belongs
    CheckVerbatim(msg, d, ABytes, o, info);
    AssertEquals(msg + ': every group the output opens it closes, as the file does',
      OpenGroups(ABytes), OpenGroups(o));
    w := LoadDoc(o, True);
    shift := 0;
    if AKind = ekDelete then shift := -1;
    AssertEquals(msg + ': paragraphs', n + shift, w.Text.ParaCount);
    for i := 0 to n - 1 do
    begin
      if i = APara then Continue;
      if i < APara then diff := ParaDiff(AFull, i, w, i) else diff := ParaDiff(AFull, i, w, i + shift);
      AssertEquals(Format('%s: paragraph %d is what it was', [msg, i]), '', diff);
    end;
    if AKind <> ekDelete then
    begin
      // the changed paragraph: the change, and the rest as it was
      expected := ParaText(AFull, APara);
      if AKind = ekInsert then
      begin
        i := CharOffset(expected, mid);
        tail := Copy(expected, i + 1, Length(expected) - i);
        SetLength(expected, i);
        Cat(expected, 'X');
        Cat(expected, tail);
      end;
      AssertRaw(msg + ': its text', expected, ParaText(w, APara));
      pe := AFull.Formats.ParaFormat(AFull.ParaFormatOf(APara));
      if AKind = ekParaFormat then pe.SpaceBefore := 77;
      AssertTrue(Format('%s: its paragraph format %s / %s', [msg, DescribePara(pe),
        DescribePara(w.Formats.ParaFormat(w.ParaFormatOf(APara)))]),
        pe.Equals(w.Formats.ParaFormat(w.ParaFormatOf(APara))));
      AssertEquals(msg + ': its cell', DescribeCell(AFull, APara), DescribeCell(w, APara));
      so := SpotsOf(AFull, APara);
      sw := SpotsOf(w, APara);
      if (AKind = ekInsert) and (len > 0) then
        AssertEquals(msg + ': its characters', Length(so) + 1, Length(sw))
      else
        AssertEquals(msg + ': its characters', Length(so), Length(sw));
      for c := 0 to High(sw) do
      begin
        // the character of the original this one is
        i := c;
        if AKind = ekInsert then
          if len = 0 then i := 0
          else if c = mid then
          begin
            // the typed one: the format of the character before it (after it at the start)
            if mid > 0 then i := mid - 1 else i := 0;
          end
          else if c > mid then i := c - 1;
        e := so[i].Format;
        if (AKind = ekCharFormat) and ((c < mid) or (len = 0)) then Include(e.Style, fsUnderline);
        // (the optional hyphen before a character is that character's alone)
        if (AKind = ekInsert) and (c = mid) and (e.Extra.Count > 0) and
           SameRaw(e.Extra.Item(e.Extra.Count - 1), '\-') then
          Continue;
        AssertTrue(Format('%s: its character %d: %s / %s', [msg, c, DescribeChar(e),
          DescribeChar(sw[c].Format)]), e.Equals(sw[c].Format));
        if not ((AKind = ekInsert) and (c = mid) and (len > 0)) then
          AssertTrue(Format('%s: its character %d: object', [msg, c]), SameObject(so[i].Obj, sw[c].Obj));
      end;
    end;
    // a file we wrote is a file we can open and save unchanged
    w2 := LoadDoc(o, False);
    o2 := SaveBytes(w2);
    AssertTrue(msg + ': saved again, ' + FirstDiff(o, o2), SameBytes(o, o2));
  finally
    w2.Free;
    w.Free;
    d.Free;
  end;
end;

procedure TTyRtfWriteTest.TestEveryParagraphEditedInTurnLeavesTheOthersAlone;
var
  names: TStringList;
  i, k, n, step: Integer;
  b: TBytes;
  full: TTyRichDocument;
  msg: string;
  kind: TEditKind;
begin
  names := TStringList.Create;
  try
    SampleNames(names);
    for i := 0 to names.Count + High(InlineSources) do
    begin
      if i < names.Count then
      begin
        msg := names[i];
        b := ReadFileBytes(FixtureDir + names[i]);
      end
      else
      begin
        msg := InlineName(i - names.Count);
        b := BytesOf(InlineSources[i - names.Count]);
      end;
      full := LoadDoc(b, True);
      try
        n := full.Text.ParaCount;
        step := 1;
        if n > 40 then step := n div 40 + 1;
        k := 0;
        while k < n do
        begin
          for kind := Low(TEditKind) to High(TEditKind) do
          begin
            // a whole paragraph is deleted where that leaves the others as they are: not
            // the last one (the one before it would take its format), not one in a table
            if (kind = ekDelete) and ((k = n - 1) or (full.CellAt(k) <> nil)) then Continue;
            CheckEdit(msg, b, full, k, kind);
          end;
          Inc(k, step);
        end;
      finally
        full.Free;
      end;
    end;
  finally
    names.Free;
  end;
end;

procedure TTyRtfWriteTest.TestAOneParagraphEditRewritesItsStretchOnly;
var
  names: TStringList;
  i, k, j, n, row: Integer;
  b, o: TBytes;
  d, full: TTyRichDocument;
  msg: string;
  info: TTyRtfWriteInfo;
  cell: TTyRichCell;
  p: TTyParaFormat;
begin
  names := TStringList.Create;
  try
    SampleNames(names);
    for i := 0 to names.Count + High(InlineSources) do
    begin
      if i < names.Count then
      begin
        msg := names[i];
        b := ReadFileBytes(FixtureDir + names[i]);
      end
      else
      begin
        msg := InlineName(i - names.Count);
        b := BytesOf(InlineSources[i - names.Count]);
      end;
      full := LoadDoc(b, True);
      try
        n := full.Text.ParaCount;
        for k := 0 to n - 1 do
        begin
          d := LoadDoc(b, False);
          try
            p := TyDefaultParaFormat;
            p.SpaceAfter := 33;
            SetPara(d, k, [pffSpaceAfter], p);
            o := SaveDoc(d, info);
            AssertTrue(Format('%s paragraph %d: saved', [msg, k]), Length(o) > 0);
            AssertEquals(Format('%s paragraph %d: one stretch', [msg, k]), 1, Length(info.Stretches));
            cell := full.CellAt(k);
            // the paragraphs of its table row; outside a table itself alone - also where
            // a group spans paragraphs (it is closed and opened again around the stretch)
            row := 0;
            if cell = nil then row := 1
            else
              for j := 0 to n - 1 do
                if (full.CellAt(j) <> nil) and (full.CellAt(j).Row = cell.Row) then Inc(row);
            AssertEquals(Format('%s paragraph %d: rewritten paragraphs', [msg, k]), row,
              info.Stretches[0].ParaCount);
            AssertTrue(Format('%s paragraph %d: it is in the stretch', [msg, k]),
              (info.Stretches[0].FirstPara <= k) and (k < info.Stretches[0].FirstPara + row));
            AssertEquals(Format('%s paragraph %d: the others copied', [msg, k]), n - row,
              info.VerbatimParas);
          finally
            d.Free;
          end;
        end;
      finally
        full.Free;
      end;
    end;
  finally
    names.Free;
  end;
end;

procedure TTyRtfWriteTest.TestTheHeaderIsOnlyAddedTo;
var
  b, o: TBytes;
  d, r: TTyRichDocument;
  info: TTyRtfWriteInfo;
  header, expected, got: RawByteString;
  at: Integer;
  f: TTyCharFormat;
  load: TTyRtfLoad;
begin
  // a new font and a new colour in a file with a font table and no colour table
  b := ReadFileBytes(FixtureDir + 're-zh-mixed.rtf');
  d := LoadDoc(b, False);
  r := nil;
  try
    load := TyRichRtfLoadOf(d);
    header := StrOf(b, 0, load.Header.Stop);
    f := Fmt('Consolas', 0, 24);
    f.Color := RGBToColor(255, 0, 0);
    SetChars(d, d.Text.ParaStart(1) + 2, 3, [cffFontName, cffCharset, cffColor], f);
    o := SaveDoc(d, info);
    // the fonts are \f0 .. \f4: the new one is \f5, before the table's closing brace, and
    // the colour table follows that brace
    at := PosRaw('Segoe UI Symbol;}}', header);
    AssertTrue('the font table ends there', at > 0);
    at := at + Length('Segoe UI Symbol;}') - 1;
    expected := Copy(header, 1, at) + '{\f5\fnil\fcharset0 Consolas;}}{\colortbl ;\red255\green0\blue0;}' +
      Copy(header, at + 2, MaxInt);
    got := StrOf(o, 0, info.HeaderStop);
    AssertRaw('the header with a font and a colour table added', expected, got);
    r := LoadDoc(o, True);
    f := r.Formats.CharFormat(r.RunsOf(1)[1].Format);
    AssertEquals('read back: the font', 'Consolas', f.FontName);
    AssertEquals('read back: its charset', 0, f.Charset);
    AssertEquals('read back: the colour', Integer(RGBToColor(255, 0, 0)), Integer(f.Color));
    AssertEquals('read back: the run', 2, r.RunsOf(1)[1].Start);
  finally
    r.Free;
    d.Free;
  end;
  // a new colour in a file that has a colour table: after its last entry; a colour the
  // table has changes nothing
  b := ReadFileBytes(FixtureDir + 're-styles.rtf');
  d := LoadDoc(b, False);
  try
    load := TyRichRtfLoadOf(d);
    header := StrOf(b, 0, load.Header.Stop);
    f := TyDefaultCharFormat;
    f.Color := RGBToColor(255, 0, 0);
    SetChars(d, d.Text.ParaStart(3), 2, [cffColor], f);
    o := SaveDoc(d, info);
    AssertRaw('a colour of the table: the header as it is', header, StrOf(o, 0, info.HeaderStop));
    f.Color := RGBToColor(1, 2, 3);
    f.HighlightColor := RGBToColor(4, 5, 6);
    SetChars(d, d.Text.ParaStart(4), 2, [cffColor, cffHighlight], f);
    o := SaveDoc(d, info);
    at := PosRaw('\red255\green255\blue0;}', header);
    AssertTrue('the colour table ends there', at > 0);
    at := at + Length('\red255\green255\blue0;') - 1;
    expected := Copy(header, 1, at) + '\red1\green2\blue3;\red4\green5\blue6;' + Copy(header, at + 1, MaxInt);
    AssertRaw('two colours added', expected, StrOf(o, 0, info.HeaderStop));
    r := LoadDoc(o, True);
    try
      f := r.Formats.CharFormat(r.RunsOf(4)[0].Format);
      AssertEquals('read back: the colour', Integer(RGBToColor(1, 2, 3)), Integer(f.Color));
      AssertEquals('read back: the highlight', Integer(RGBToColor(4, 5, 6)), Integer(f.HighlightColor));
      f := r.Formats.CharFormat(r.RunsOf(3)[0].Format);
      AssertEquals('read back: the table''s red', Integer(RGBToColor(255, 0, 0)), Integer(f.Color));
    finally
      r.Free;
    end;
  finally
    d.Free;
  end;
  // a file with no font table: the text without a font must stay without one
  b := BytesOf('{\rtf1 A\par B\par C\par}');
  d := LoadDoc(b, False);
  try
    SetChars(d, d.Text.ParaStart(1), 1, [cffFontName, cffCharset], Fmt('Consolas', 0, 0));
    o := SaveDoc(d, info);
    r := LoadDoc(o, True);
    try
      AssertEquals('paragraphs', 3, r.Text.ParaCount);
      AssertEquals('the font', 'Consolas', r.Formats.CharFormat(r.RunsOf(1)[0].Format).FontName);
      AssertEquals('A has no font: ' + Shown(StrOf(o, 0, Length(o))), '',
        r.Formats.CharFormat(r.RunsOf(0)[0].Format).FontName);
      AssertEquals('C has no font', '', r.Formats.CharFormat(r.RunsOf(2)[0].Format).FontName);
    finally
      r.Free;
    end;
  finally
    d.Free;
  end;
end;

procedure TTyRtfWriteTest.TestEveryFormatFieldSurvivesWriteAndRead;
var
  chars: array of TTyCharFormat;
  paras: array of TTyParaFormat;
  base: TTyCharFormat;
  i: Integer;
  d, r: TTyRichDocument;
  o: TBytes;
  got: TTyCharFormat;
  gotP: TTyParaFormat;

  function C: Integer;
  begin
    SetLength(chars, Length(chars) + 1);
    Result := High(chars);
    chars[Result] := base;
  end;

  function P: Integer;
  begin
    SetLength(paras, Length(paras) + 1);
    Result := High(paras);
    paras[Result] := TyDefaultParaFormat;
  end;

begin
  base := Fmt('Arial', 0, 24);
  chars := nil;
  paras := nil;
  // every field of a character format, alone
  C;
  i := C; chars[i].FontName := 'Times New Roman';
  i := C; chars[i].FontName := ZhSongTi; chars[i].Charset := 134;
  i := C; chars[i].FontName := 'MS Mincho'; chars[i].Charset := 128;
  i := C; chars[i].FontName := 'Symbol'; chars[i].Charset := 2;
  i := C; chars[i].Charset := 204;
  i := C; chars[i].SizeHalfPt := 15;
  i := C; chars[i].SizeHalfPt := 144;
  i := C; chars[i].Style := [fsBold];
  i := C; chars[i].Style := [fsItalic];
  i := C; chars[i].Style := [fsUnderline];
  i := C; chars[i].Style := [fsBold, fsItalic, fsUnderline];
  i := C; chars[i].Strike := True;
  i := C; chars[i].VertAlign := vaSuper;
  i := C; chars[i].VertAlign := vaSub;
  i := C; chars[i].Color := RGBToColor(10, 20, 30);
  i := C; chars[i].Color := RGBToColor(0, 0, 0);
  i := C; chars[i].HighlightColor := RGBToColor(200, 100, 50);
  i := C; chars[i].Extra.Add('\lang1033');
  i := C; chars[i].Extra.Add('\kerning2 '); chars[i].Extra.Add('\cs15'); chars[i].Extra.Add('{\*\oldcprops \b}');
  i := C; chars[i].Extra.Add('\rtlch'); chars[i].Extra.Add('\af3 '); chars[i].Extra.Add('\ltrch');
  // every field of a paragraph format, alone
  P;
  i := P; paras[i].Align := paraCenter;
  i := P; paras[i].Align := paraRight;
  i := P; paras[i].Align := paraJustify;
  i := P; paras[i].LeftIndent := 720;
  i := P; paras[i].RightIndent := 360;
  i := P; paras[i].FirstIndent := 300;
  i := P; paras[i].FirstIndent := -300;
  i := P; paras[i].SpaceBefore := 120;
  i := P; paras[i].SpaceAfter := 60;
  i := P; paras[i].LineSpacing := ls115;
  i := P; paras[i].LineSpacing := ls15;
  i := P; paras[i].LineSpacing := lsDouble;
  i := P; paras[i].LineSpacing := lsExact; paras[i].LineSpacingValue := 280;
  i := P; paras[i].LineSpacing := lsAtLeast; paras[i].LineSpacingValue := 310;
  i := P; SetLength(paras[i].Tabs, 1); paras[i].Tabs[0].Position := 2000;
  i := P; SetLength(paras[i].Tabs, 2); paras[i].Tabs[0].Position := 1000; paras[i].Tabs[0].Align := ttaCenter;
  paras[i].Tabs[1].Position := 3000; paras[i].Tabs[1].Align := ttaRight; paras[i].Tabs[1].Leader := ttlDot;
  i := P; SetLength(paras[i].Tabs, 4);
  paras[i].Tabs[0].Position := 500; paras[i].Tabs[0].Align := ttaDecimal; paras[i].Tabs[0].Leader := ttlHyphen;
  paras[i].Tabs[1].Position := 600; paras[i].Tabs[1].Leader := ttlUnderline;
  paras[i].Tabs[2].Position := 700; paras[i].Tabs[2].Leader := ttlThick;
  paras[i].Tabs[3].Position := 800; paras[i].Tabs[3].Leader := ttlEqual;
  i := P; paras[i].RtlPar := True;
  i := P; paras[i].Extra.Add('\keepn');
  i := P; paras[i].Extra.Add('\s4 '); paras[i].Extra.Add('\widctlpar'); paras[i].Extra.Add('\brdrb'); paras[i].Extra.Add('{\*\oldpprops \qc}');
  // a line spacing the model has no name for is kept as its words
  i := P; paras[i].Extra.Add('\sl288'); paras[i].Extra.Add('\slmult1');
  // lists as a file has them: the words of {\*\pn} the model keeps as Extra, in Extra
  i := P; paras[i].List.Kind := lkBullet; paras[i].Extra.Add('\pnf7'); paras[i].Extra.Add('\pnindent0'); paras[i].Extra.Add('{\pntxtb\''B7}');
  i := P; paras[i].List.Kind := lkDecimal; paras[i].List.StartAt := 1; paras[i].Extra.Add('{\pntxta)}');
  i := P; paras[i].List.Kind := lkLowerAlpha; paras[i].List.StartAt := 4; paras[i].Extra.Add('{\pntxta.}');
  i := P; paras[i].List.Kind := lkUpperAlpha; paras[i].List.StartAt := 2; paras[i].List.Level := 2; paras[i].Extra.Add('{\pntxta.}');
  i := P; paras[i].List.Kind := lkLowerRoman; paras[i].List.StartAt := 1; paras[i].Extra.Add('\keep'); paras[i].Extra.Add('{\pntxta.}'); paras[i].Extra.Add('\keepn');
  i := P; paras[i].List.Kind := lkUpperRoman; paras[i].List.StartAt := 9; paras[i].Extra.Add('{\pntxta.}');
  for i := 0 to High(chars) do
  begin
    d := TTyRichDocument.Create;
    r := nil;
    try
      d.Execute(TTyRichInsertText.Create(0, 'abc'));
      SetChars(d, 0, 3, AllChar, chars[i]);
      o := SaveBytes(d);
      r := LoadDoc(o, True);
      AssertEquals(Format('character format %d: one run', [i]), 1, Length(r.RunsOf(0)));
      got := r.Formats.CharFormat(r.RunsOf(0)[0].Format);
      AssertTrue(Format('character format %d: %s / %s in %s', [i, DescribeChar(chars[i]),
        DescribeChar(got), Shown(StrOf(o, 0, Length(o)))]), chars[i].Equals(got));
      AssertRaw(Format('character format %d: text', [i]), 'abc', ParaText(r, 0));
    finally
      r.Free;
      d.Free;
    end;
  end;
  // unknown words on text in the theme's font (no font and no size to write after them):
  // the last one must not gain a delimiter it did not have
  d := TTyRichDocument.Create;
  r := nil;
  try
    d.Execute(TTyRichInsertText.Create(0, 'abc'));
    got := TyDefaultCharFormat;
    got.Extra.Add('\kerning2 ');
    got.Extra.Add('\lang1033');
    SetChars(d, 0, 3, [cffExtra], got);
    o := SaveBytes(d);
    r := LoadDoc(o, True);
    AssertRaw('theme font: text in ' + Shown(StrOf(o, 0, Length(o))), 'abc', ParaText(r, 0));
    got := r.Formats.CharFormat(r.RunsOf(0)[0].Format);
    AssertEquals('theme font: no font', '', got.FontName);
    AssertEquals('theme font: the unknown words', 2, got.Extra.Count);
    AssertRaw('theme font: the first', '\kerning2 ', got.Extra.Item(0));
    AssertRaw('theme font: the last', '\lang1033', got.Extra.Item(1));
  finally
    r.Free;
    d.Free;
  end;
  for i := 0 to High(paras) do
  begin
    d := TTyRichDocument.Create;
    r := nil;
    try
      d.Execute(TTyRichInsertText.Create(0, 'abc' + #10 + 'next'));
      SetChars(d, 0, d.Text.Length, AllChar, base);
      SetPara(d, 0, AllPara, paras[i]);
      o := SaveBytes(d);
      r := LoadDoc(o, True);
      gotP := r.Formats.ParaFormat(r.ParaFormatOf(0));
      AssertTrue(Format('paragraph format %d: %s / %s in %s', [i, DescribePara(paras[i]),
        DescribePara(gotP), Shown(StrOf(o, 0, Length(o)))]), paras[i].Equals(gotP));
      AssertTrue(Format('paragraph format %d: the next paragraph is plain', [i]),
        TyDefaultParaFormat.Equals(r.Formats.ParaFormat(r.ParaFormatOf(1))));
      AssertTrue(Format('paragraph format %d: characters', [i]),
        base.Equals(r.Formats.CharFormat(r.RunsOf(0)[0].Format)));
    finally
      r.Free;
      d.Free;
    end;
  end;
end;

procedure TTyRtfWriteTest.TestListsAreWrittenAsRichEditWritesThem;
var
  d: TTyRichDocument;
  o: TBytes;
  text: RawByteString;
  b: TBytes;
  info: TTyRtfWriteInfo;
  p: TTyParaFormat;
begin
  d := BuildOwnDocument;
  try
    o := SaveBytes(d);
    text := StrOf(o, 0, Length(o));
    // the fonts: \f0 is the default font's and that has no name here; \f1 Arial, \f2 the
    // Chinese one, \f3 Symbol for the bullets
    AssertTrue('Symbol in the font table: ' + Shown(text), PosRaw('\fnil\fcharset2 Symbol;}', text) > 0);
    AssertTrue('a bullet as RichEdit writes it: ' + Shown(text),
      PosRaw('\pard{\pntext\f3\''B7\tab}{\*\pn\pnlvlblt\pnf3\pnindent0{\pntxtb\''B7}}\fi-360\li720', text) > 0);
    AssertTrue('the next bullets: only their text', PosRaw('\par' + #13#10 + '{\pntext\f3\''B7\tab}bullet b', text) > 0);
    AssertTrue('a numbered list from 3: ' + Shown(text),
      PosRaw('\pard{\pntext\f1 3.\tab}{\*\pn\pnlvlbody\pnf1\pnindent0\pnstart3\pndec{\pntxta.}}\fi-360\li720', text) > 0);
    AssertTrue('its second item is 4', PosRaw('{\pntext\f1 4.\tab}fourth', text) > 0);
    AssertTrue('upper roman, level 1: ' + Shown(text),
      PosRaw('{\pntext\f1 I.\tab}{\*\pn\pnlvl2\pnf1\pnindent0\pnstart1\pnucrm{\pntxta.}}', text) > 0);
    // a table as RichEdit writes it
    AssertTrue('a row: ' + Shown(text), PosRaw('\trowd\trgaph108\cellx2400\cellx4800\pard\intbl', text) > 0);
    AssertTrue('a paragraph inside a cell ends with \par, the cell with \cell, the row with \row: ' + Shown(text),
      PosRaw('r0c0\cell r0c1 first\par' + #13#10, text) > 0);
    AssertTrue('the row''s end', PosRaw(' second\cell\row' + #13#10, text) > 0);
    // a picture made here: its format, its display size, its bytes in hex
    AssertTrue('a picture: ' + Shown(text), PosRaw('{\pict\pngblip\picwgoal720\pichgoal480 89504e470d0a1a0a', text) > 0);
    AssertTrue('an unknown block as its bytes', PosRaw('{\*\tyunknown some {nested} thing}', text) > 0);
  finally
    d.Free;
  end;
  // an item of a file's list rewritten: its number is its place in the list
  b := ReadFileBytes(FixtureDir + 're-zh-list.rtf');
  d := LoadDoc(b, False);
  try
    p := TyDefaultParaFormat;
    p.SpaceBefore := 20;
    SetPara(d, 7, [pffSpaceBefore], p);
    o := SaveDoc(d, info);
    text := StrOf(o, info.Stretches[0].OutStart, info.Stretches[0].OutStop - info.Stretches[0].OutStart);
    AssertTrue('the third item of the numbered list: ' + Shown(text),
      PosRaw('{\pntext\f0 3.\tab}{\*\pn\pnlvlbody\pndec\pnstart1\pnf0\pnindent0{\pntxta.}}', text) > 0);
    SetPara(d, 3, [pffSpaceBefore], p);
    o := SaveDoc(d, info);
    text := StrOf(o, info.Stretches[0].OutStart, info.Stretches[0].OutStop - info.Stretches[0].OutStart);
    AssertTrue('the second bullet: ' + Shown(text),
      PosRaw('{\pntext\f1\''B7\tab}{\*\pn\pnlvlblt\pnf1\pnindent0{\pntxtb\''B7}}', text) > 0);
  finally
    d.Free;
  end;
end;

procedure TTyRtfWriteTest.TestSavingAnUnchangedBigDocumentCopiesRanges;
var
  b: TBytes;
  d: TTyRichDocument;
  load: TTyRtfLoad;
  s: TCheckStream;
  visits: Int64;
  info: TTyRtfWriteInfo;
begin
  b := Generate('re-zh-mixed.rtf', 20 * MB);
  d := LoadDoc(b, False);
  try
    load := TyRichRtfLoadOf(d);
    AssertTrue('a quarter of a million paragraphs', d.Text.ParaCount > 100000);
    AssertEquals('nothing parsed by loading', 0, load.ParseCount);
    visits := d.Text.NodeVisits;
    s := TCheckStream.Create(b);
    try
      TyRichSaveRtf(d, s, info);
      AssertEquals('byte for byte (first difference at)', -1, s.Mismatch);
      AssertEquals('all of it', Length(b), s.Written);
      // the header, the paragraphs as one block, the trailer: not a write per paragraph
      AssertTrue(Format('%d writes', [s.Writes]), s.Writes <= 4);
      AssertTrue(Format('the heap grew by %d bytes while saving', [s.HeapPeak - s.HeapBase]),
        s.HeapPeak - s.HeapBase <= MB);
    finally
      s.Free;
    end;
    AssertEquals('no interval parsed', 0, load.ParseCount);
    AssertEquals('no paragraph rewritten', 0, Length(info.Stretches));
    // the paragraphs are walked, not looked up one by one
    AssertTrue(Format('%d tree nodes visited for %d paragraphs', [d.Text.NodeVisits - visits,
      d.Text.ParaCount]), d.Text.NodeVisits - visits < 1000);
  finally
    d.Free;
  end;
end;

procedure TTyRtfWriteTest.TestTheLastParagraphWithoutATerminator;
var
  d, r: TTyRichDocument;
  o: TBytes;
  info: TTyRtfWriteInfo;
  text: RawByteString;
  i, depth: Integer;
begin
  // '{\rtf1 A\par B}': B has no \par. Typing a new paragraph after it: B cannot go back as
  // its bytes (the new paragraph would join it)
  d := LoadDoc(BytesOf('{\rtf1 A\par B}'), False);
  r := nil;
  try
    d.Execute(TTyRichInsertText.Create(d.Text.Length, #10 + 'C'));
    AssertEquals('three paragraphs', 3, d.Text.ParaCount);
    o := SaveDoc(d, info);
    r := LoadDoc(o, True);
    AssertEquals('read back: paragraphs in ' + Shown(StrOf(o, 0, Length(o))), 3, r.Text.ParaCount);
    AssertRaw('A', 'A', ParaText(r, 0));
    AssertRaw('B', 'B', ParaText(r, 1));
    AssertRaw('C', 'C', ParaText(r, 2));
    AssertEquals('A is copied', 1, info.VerbatimParas);
  finally
    FreeAndNil(r);
    d.Free;
  end;
  // changing A leaves B as its bytes: it is still the last
  d := LoadDoc(BytesOf('{\rtf1 A\par B}'), False);
  try
    d.Execute(TTyRichInsertText.Create(0, 'x'));
    o := SaveDoc(d, info);
    AssertEquals('B is copied', 1, info.VerbatimParas);
    AssertTrue('and ends the file as it did', SameRaw(StrOf(o, Length(o) - 2, 2), 'B}'));
    r := LoadDoc(o, True);
    AssertEquals('read back: paragraphs', 2, r.Text.ParaCount);
    AssertRaw('xA', 'xA', ParaText(r, 0));
    AssertRaw('B', 'B', ParaText(r, 1));
  finally
    FreeAndNil(r);
    d.Free;
  end;
  // the last paragraphs deleted: the file ends after what is left
  d := LoadDoc(BytesOf('{\rtf1 A\par B\par C\par D\par}'), False);
  try
    d.Execute(TTyRichDelete.Create(d.Text.ParaStart(2) - 1, d.Text.Length - d.Text.ParaStart(2) + 1));
    AssertEquals('two paragraphs left', 2, d.Text.ParaCount);
    o := SaveDoc(d, info);
    r := LoadDoc(o, True);
    AssertEquals('read back: paragraphs in ' + Shown(StrOf(o, 0, Length(o))), 2, r.Text.ParaCount);
    AssertRaw('B', 'B', ParaText(r, 1));
  finally
    FreeAndNil(r);
    d.Free;
  end;
  // a body that ends inside a group: the braces still pair up when its end is rewritten
  d := LoadDoc(BytesOf('{\rtf1{\fonttbl{\f0 Arial;}}\f0 one\par {\b A\par B\par}}'), False);
  try
    d.Execute(TTyRichInsertText.Create(d.Text.Length, '!'));
    o := SaveDoc(d, info);
    text := StrOf(o, 0, Length(o));
    depth := 0;
    for i := 1 to Length(text) do
    begin
      if text[i] = '{' then Inc(depth) else if text[i] = '}' then Dec(depth);
      if (depth = 0) and (i < Length(text)) then Fail('the document closes early: ' + Shown(text));
    end;
    AssertEquals('braces pair up: ' + Shown(text), 0, depth);
    r := LoadDoc(o, True);
    AssertEquals('read back: paragraphs', 3, r.Text.ParaCount);
    AssertRaw('the last one', 'B!', ParaText(r, 2));
    AssertTrue('still bold', fsBold in r.Formats.CharFormat(r.RunsOf(2)[0].Format).Style);
    AssertTrue('A too', fsBold in r.Formats.CharFormat(r.RunsOf(1)[0].Format).Style);
  finally
    FreeAndNil(r);
    d.Free;
  end;
  // an empty file is one empty paragraph
  d := LoadDoc(BytesOf('{\rtf1}'), False);
  try
    o := SaveDoc(d, info);
    AssertRaw('as it was', '{\rtf1}', StrOf(o, 0, Length(o)));
    d.Execute(TTyRichInsertText.Create(0, 'hello'));
    o := SaveDoc(d, info);
    r := LoadDoc(o, True);
    AssertEquals('read back: one paragraph', 1, r.Text.ParaCount);
    AssertRaw('its text', 'hello', ParaText(r, 0));
  finally
    FreeAndNil(r);
    d.Free;
  end;
end;

procedure TTyRtfWriteTest.TestRefusesWhatItCannotSave;
var
  b: TBytes;
  d: TTyRichDocument;
  s, o: TBytesStream;
  load: TTyRtfLoad;
  raised: Boolean;
  depth, i: Integer;
  info: TTyRtfWriteInfo;
  r, full: TTyRichDocument;
begin
  b := Generate('re-zh-mixed.rtf', 2 * MB);
  d := TTyRichDocument.Create;
  s := TBytesStream.Create(b);
  o := TBytesStream.Create;
  try
    load := TyRichBeginLoadRtf(d, s, 64 * 1024);
    AssertTrue('still loading', d.Loading);
    raised := False;
    try
      TyRichSaveRtf(d, o);
    except
      on E: ETyRichRtfWrite do raised := True;
    end;
    AssertTrue('a document that is still loading is not saved', raised);
    AssertEquals('nothing written', 0, o.Size);
    load.Cancel;
    AssertTrue('cancelled: only a part of the file', d.Incomplete);
    raised := False;
    try
      TyRichSaveRtf(d, o);
    except
      on E: ETyRichRtfWrite do raised := True;
    end;
    AssertTrue('a part of a file is not saved as the file', raised);
    AssertEquals('nothing written', 0, o.Size);
  finally
    o.Free;
    s.Free;
    d.Free;
  end;
  // saving changes nothing in the document
  d := LoadDoc(ReadFileBytes(FixtureDir + 're-styles.rtf'), False);
  o := TBytesStream.Create;
  try
    TyRichSaveRtf(d, o);
    AssertFalse('not modified by saving', d.Modified);
    d.Execute(TTyRichInsertText.Create(3, 'X'));
    depth := d.UndoDepth;
    AssertTrue('modified by the edit', d.Modified);
    TyRichSaveRtf(d, o);
    AssertTrue('still modified: the caller says when it is saved', d.Modified);
    AssertEquals('the history stays', depth, d.UndoDepth);
    // a paragraph deleted and brought back is the file's own again (typed text undone
    // leaves its paragraph as text of the document: equal, but written from the model)
    d.Undo;
    d.Execute(TTyRichDelete.Create(d.Text.ParaStart(2), d.Text.ParaLength(2) + 1));
    d.Undo;
    o.Clear;
    TyRichSaveRtf(d, o, info);
    AssertEquals('only the paragraph that was typed in is rewritten', 1, info.RewrittenParas);
    r := LoadDoc(Copy(o.Bytes, 0, o.Size), True);
    full := LoadDoc(ReadFileBytes(FixtureDir + 're-styles.rtf'), True);
    try
      AssertEquals('undone: the paragraphs', full.Text.ParaCount, r.Text.ParaCount);
      for i := 0 to full.Text.ParaCount - 1 do
        AssertEquals(Format('undone: paragraph %d', [i]), '', ParaDiff(full, i, r, i));
    finally
      full.Free;
      r.Free;
    end;
  finally
    o.Free;
    d.Free;
  end;
end;

initialization
  RegisterTest(TTyRtfWriteTest);
end.
