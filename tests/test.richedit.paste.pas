unit test.richedit.paste;

{ TTyRichEdit pasting (Task 10c): RTF first, then a picture, then plain text, as one undoable
  command through the door of every user edit (ReadOnly, the input method, the refusals), the
  RTF read by the engine's own reader and inserted as a fragment (TTyRichInsertFragment), a
  picture as one picture object stored as PNG, plain text as paragraphs in the caret's
  paragraph format; the round trip of every fixture's ranges through the range writer and a
  paste; what a one-line paste costs in a document of two million lines.

  Headless, on the editor probe (test.richedit.edit's TEditProbe on test.richedit.control's
  TRichProbe): the clipboard is the probe's double - its flavours are fields, its reads are
  counted - and never the system's. No window, no message loop. Every bound is a count. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, fpcunit, testregistry, Controls, Graphics, LCLType, Forms,
  BGRABitmap, BGRABitmapTypes, BGRAWritePNG, BGRAReadPng,
  tyControls.Controller, tyControls.TextMenu, tyControls.StrConsts,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.Commands,
  tyControls.RichEdit.TextIO, tyControls.RichEdit.RtfRead, tyControls.RichEdit.RtfWrite,
  tyControls.RichEdit.Layout, tyControls.RichEdit, test.richedit.layoutdevice,
  test.richedit.control, test.richedit.edit;

type
  TTyRichEditPasteTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FRich: TEditProbe;
    FChanges, FSelChanges: Integer;
    FRaiseOnChange: Boolean;
    FSaveCalls, FSaveRefused: Integer;
    procedure Changed(Sender: TObject);
    procedure SelChanged(Sender: TObject);
    procedure PasteWhileSaving(Sender: TObject; ADone, ATotal: Int64; var ACancel: Boolean);
    procedure ResetEvents;
    procedure LoadRtf(const S: RawByteString);
    procedure LoadBytes(const B: TBytes);
    procedure SetText(const S: string);
    procedure Clip(const ARtf: RawByteString; const AText: string; const APicture: TBytes = nil;
      AKind: TTyRichImageKind = rikPng);
    function Para(AIndex: Integer): RawByteString;
    function CharFormatAt(APos: TTyRichPos): TTyCharFormat;
    function ObjectAt(APos: TTyRichPos): TTyRichObject;
    procedure PaintAll;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    // the brief's
    procedure TestPastePrefersRtfThenPictureThenText;
    // one per rule
    procedure TestAFlavourThatCannotBeUsedFallsThrough;
    procedure TestHtmlIsNoFlavourOfOurs;
    procedure TestAPasteIsOneStepAndUndoPutsTheSelectionBack;
    procedure TestAPasteIsNeverMergedWithTyping;
    procedure TestEveryRefusalOfAPaste;
    procedure TestReadOnlyPastesNothing;
    procedure TestEachEntryEndsTheCompositionFirst;
    procedure TestRtfJoinsReplacingSelections;
    procedure TestRowsAreRowsOutsideATableAndTextInOne;
    procedure TestTheSourcesDefaultFontAndNoDocumentLevelThing;
    procedure TestEveryFixturesRangesPasteBackAsTheRange;
    procedure TestAWholeFixturePastedAndSavedReadsBack;
    procedure TestUntrustedRtfFromTheClipboard;
    procedure TestAPictureFromADib;
    procedure TestAPngIsKeptAndAPictureIsSavedAndReadBack;
    procedure TestAPictureWiderThanTheTextIsScaledAndTooLargeIsRefused;
    procedure TestPlainTextLinesAndCharacters;
    procedure TestPlainTextThatIsNotUtf8AndInACell;
    procedure TestCanPasteReadsNothing;
    procedure TestAOneLinePasteInALargeDocumentTouchesOneParagraph;
    procedure TestTheWaitCursorOverTheThreshold;
  end;

implementation

const
  BS = '\';
  BigLines = 2000000;

var
  GBig: TBytes;

{ ---- helpers ---- }

function U(ACode: Cardinal): RawByteString;
begin
  if ACode < $80 then Result := AnsiChar(ACode)
  else if ACode < $800 then
    Result := AnsiChar($C0 or (ACode shr 6)) + AnsiChar($80 or (ACode and $3F))
  else if ACode < $10000 then
    Result := AnsiChar($E0 or (ACode shr 12)) + AnsiChar($80 or ((ACode shr 6) and $3F)) +
      AnsiChar($80 or (ACode and $3F))
  else
    Result := AnsiChar($F0 or (ACode shr 18)) + AnsiChar($80 or ((ACode shr 12) and $3F)) +
      AnsiChar($80 or ((ACode shr 6) and $3F)) + AnsiChar($80 or (ACode and $3F));
  SetCodePage(Result, CP_UTF8, False);
end;

function RawBytes(const S: RawByteString): TBytes;
begin
  Result := nil;
  SetLength(Result, Length(S));
  if S <> '' then Move(S[1], Result[0], Length(S));
end;

function StrOfBytes(const B: TBytes): RawByteString;
begin
  Result := '';
  SetLength(Result, Length(B));
  if Length(B) > 0 then Move(B[0], Result[1], Length(B));
end;

function SameRaw(const A, B: RawByteString): Boolean;
begin
  Result := (Length(A) = Length(B)) and ((A = '') or CompareMem(@A[1], @B[1], Length(A)));
end;

function Shown(const S: RawByteString): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do
    if (S[i] >= ' ') and (S[i] < #$7F) then Result := Result + S[i]
    else Result := Result + '<' + IntToHex(Ord(S[i]), 2) + '>';
  if Length(Result) > 200 then Result := Copy(Result, 1, 200) + '...';
end;

function FileBytes(const APath: string): TBytes;
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

function FixtureDir: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'tests' + PathDelim + 'fixtures' +
    PathDelim + 'rtf' + PathDelim;
end;

function BigText: TBytes;
var
  ms: TMemoryStream;
  i: Integer;
  s: RawByteString;
begin
  if GBig = nil then
  begin
    ms := TMemoryStream.Create;
    try
      ms.Size := 16 * Int64(BigLines);
      ms.Position := 0;
      for i := 1 to BigLines do
      begin
        s := 'Line ' + IntToStr(i);
        if i < BigLines then s := s + #10;
        ms.WriteBuffer(s[1], Length(s));
      end;
      SetLength(GBig, ms.Position);
      Move(ms.Memory^, GBig[0], ms.Position);
    finally
      ms.Free;
    end;
  end;
  Result := GBig;
end;

function ParaText(ADoc: TTyRichDocument; AIndex: Integer): RawByteString;
begin
  Result := ADoc.Text.GetText(ADoc.Text.ParaStart(AIndex), ADoc.Text.ParaLength(AIndex));
  SetCodePage(Result, CP_UTF8, False);
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

function RangeOut(ADoc: TTyRichDocument; AFrom, ALen: TTyRichPos): TBytes;
var
  s: TBytesStream;
begin
  s := TBytesStream.Create;
  try
    TyRichSaveRtfRange(ADoc, s, AFrom, ALen);
    Result := Copy(s.Bytes, 0, s.Size);
  finally
    s.Free;
  end;
end;

function SaveOut(ADoc: TTyRichDocument): TBytes;
var
  s: TBytesStream;
begin
  s := TBytesStream.Create;
  try
    TyRichSaveRtf(ADoc, s);
    Result := Copy(s.Bytes, 0, s.Size);
  finally
    s.Free;
  end;
end;

{ ABytes read as a clipboard's RTF and inserted at APos of ADoc, as the control does it. }
function PasteInto(ADoc: TTyRichDocument; APos: TTyRichPos; const ABytes: TBytes): Boolean;
var
  src: TTyRichDocument;
  ends: Boolean;
begin
  src := TyRichReadRtfFragment(ABytes, ends);
  Result := src <> nil;
  if Result then ADoc.Execute(TTyRichInsertFragment.Create(APos, src, ends));
end;

function SameObject(A, B: TTyRichObject): Boolean;
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
    (pa.HeightTwips = pb.HeightTwips) and (Length(pa.Data) = Length(pb.Data)) and
    ((Length(pa.Data) = 0) or CompareMem(@pa.Data[0], @pb.Data[0], Length(pa.Data)));
end;

type
  TCharSpot = record
    Format: TTyCharFormat;
    Obj: TTyRichObject;
  end;
  TCharSpots = array of TCharSpot;

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

function Describe(const F: TTyCharFormat): string;
var
  i: Integer;
begin
  Result := Format('%s/%d %d st%d k%d v%d c%x h%x [', [Shown(F.FontName), F.Charset,
    F.SizeHalfPt, Integer(F.Style), Ord(F.Strike), Ord(F.VertAlign), F.Color, F.HighlightColor]);
  for i := 0 to F.Extra.Count - 1 do Result := Result + Shown(F.Extra.Item(i)) + '|';
  Result := Result + ']';
end;

{ A saved document of its own has no list table of a file: a Word list's \ls and \ilvl
  (references into the source's tables) are not written - the list is written from its kind
  (the writer's rule) - so they are not compared there. }
function SamePara(const A, B: TTyParaFormat; ASaved: Boolean): Boolean;

  function Stripped(const F: TTyParaFormat): TTyParaFormat;
  var
    i, param: Integer;
  begin
    Result := F;
    Result.Extra.Clear;
    for i := 0 to F.Extra.Count - 1 do
      if not (TyRtfParaExtraKind(F.Extra.Item(i), param) in [pekLs, pekIlvl]) then
        Result.Extra.Add(F.Extra.Item(i));
  end;

begin
  if not ASaved then Exit(A.Equals(B));
  Result := Stripped(A).Equals(Stripped(B));
end;

{ What a paste of [AFrom, AFrom + ALen) of A left in B, which had AHead characters before the
  place in its paragraph AK (the paragraph the paste went into): '' when B holds the range -
  every paragraph's text, every character's format and object, the format of every paragraph
  pasted with its mark, and the cells of rows pasted as rows. }
function PasteDiff(A: TTyRichDocument; AFrom, ALen: TTyRichPos; B: TTyRichDocument; AK: Integer;
  AHead: Integer; ASaved: Boolean = False): string;
var
  R: TTyRichCopyRange;
  k, j, i, bk, off: Integer;
  c0, c1: TTyRichPos;
  ta, tb: RawByteString;
  sa, sb: TCharSpots;
  ca, cb: TTyRichCell;
  fa, fb: TTyCharFormat;
begin
  R := TyRichCopyRange(A, AFrom, ALen);
  if R.Empty then Exit('');
  // rows pasted after text: the text kept a paragraph of its own
  if (AHead > 0) and not R.InOneCell and (A.CellAt(R.FirstPara) <> nil) then
  begin
    Inc(AK);
    AHead := 0;
  end;
  for k := R.FirstPara to R.LastPara do
  begin
    j := k - R.FirstPara;
    bk := AK + j;
    if bk >= B.Text.ParaCount then Exit(Format('paragraph %d: none pasted', [k]));
    c0 := 0;
    c1 := A.Text.ParaLength(k);
    if k = R.FirstPara then c0 := R.FromChar;
    if k = R.LastPara then c1 := R.ToChar;
    if j = 0 then off := AHead else off := 0;
    ta := ParaText(A, k);
    ta := Copy(ta, CharOffset(ta, c0) + 1, CharOffset(ta, c1) - CharOffset(ta, c0));
    tb := ParaText(B, bk);
    tb := Copy(tb, CharOffset(tb, off) + 1, Length(ta));
    if not SameRaw(ta, tb) then
      Exit(Format('paragraph %d: text <%s> / <%s>', [k, Shown(ta), Shown(tb)]));
    if c1 > c0 then
    begin
      sa := SpotsOf(A, k);
      sb := SpotsOf(B, bk);
      for i := c0 to c1 - 1 do
      begin
        fa := sa[i].Format;
        fb := sb[i - c0 + off].Format;
        // a run that names no font is shown in A's default one, which the paste names
        if fa.FontName = '' then
        begin
          fa.FontName := A.DefaultCharFormat.FontName;
          if fa.FontName <> '' then fa.Charset := A.DefaultCharFormat.Charset;
        end;
        if fa.SizeHalfPt = 0 then fa.SizeHalfPt := A.DefaultCharFormat.SizeHalfPt;
        { Saved: a font with no charset of its own is written with the one its text calls for
          (the writer's rule for a document of its own), and reads back with it. }
        if ASaved and (fa.Charset = DEFAULT_CHARSET) then fa.Charset := fb.Charset;
        if not fa.Equals(fb) then
          Exit(Format('paragraph %d character %d: %s / %s', [k, i, Describe(fa), Describe(fb)]));
        if not SameObject(sa[i].Obj, sb[i - c0 + off].Obj) then
          Exit(Format('paragraph %d character %d: the object', [k, i]));
      end;
    end;
    // a paragraph pasted with its mark has its own format (Word's rule)
    if (k < R.LastPara) or R.LastSeparator then
      if not SamePara(A.Formats.ParaFormat(A.ParaFormatOf(k)), B.Formats.ParaFormat(B.ParaFormatOf(bk)),
        ASaved) then
        Exit(Format('paragraph %d: its format', [k]));
    ca := A.CellAt(k);
    cb := B.CellAt(bk);
    if R.InOneCell then
    begin
      if cb <> nil then Exit(Format('paragraph %d: in a table, copied from one cell', [k]));
    end
    else if (ca = nil) <> (cb = nil) then
      Exit(Format('paragraph %d: a cell / none', [k]))
    else if (ca <> nil) and ((ca.Index <> cb.Index) or (ca.Row.CellCount <> cb.Row.CellCount)) then
      Exit(Format('paragraph %d: cell %d of %d / %d of %d', [k, ca.Index, ca.Row.CellCount,
        cb.Index, cb.Row.CellCount]));
  end;
  Result := '';
end;

{ A 32-bit bottom-up DIB of AW x AH pixels in AColor (B, G, R, A), AXppm pixels a metre. }
function MakeDib(AW, AH: Integer; AB, AG, AR, AA: Byte; AXppm: Integer = 0): TBytes;
var
  i: Integer;
  p: PByte;

  procedure Put32(AAt: Integer; V: LongInt);
  begin
    Result[AAt] := V and $FF;
    Result[AAt + 1] := (V shr 8) and $FF;
    Result[AAt + 2] := (V shr 16) and $FF;
    Result[AAt + 3] := (V shr 24) and $FF;
  end;

begin
  Result := nil;
  SetLength(Result, 40 + AW * AH * 4);
  FillChar(Result[0], Length(Result), 0);
  Put32(0, 40);
  Put32(4, AW);
  Put32(8, AH);
  Result[12] := 1;
  Result[14] := 32;
  Put32(20, AW * AH * 4);
  Put32(24, AXppm);
  Put32(28, AXppm);
  p := @Result[40];
  for i := 0 to AW * AH - 1 do
  begin
    p[0] := AB;
    p[1] := AG;
    p[2] := AR;
    p[3] := AA;
    Inc(p, 4);
  end;
end;

function MakePng(AW, AH: Integer; const AColor: TBGRAPixel): TBytes;
var
  bmp: TBGRABitmap;
  w: TBGRAWriterPNG;
  st: TBytesStream;
begin
  bmp := TBGRABitmap.Create(AW, AH, AColor);
  w := TBGRAWriterPNG.Create;
  st := TBytesStream.Create;
  try
    w.UseAlpha := True;
    bmp.SaveToStream(st, w);
    Result := Copy(st.Bytes, 0, st.Size);
  finally
    st.Free;
    w.Free;
    bmp.Free;
  end;
end;

function DecodePng(const B: TBytes): TBGRABitmap;
var
  st: TBytesStream;
begin
  st := TBytesStream.Create(B);
  try
    Result := TBGRABitmap.Create;
    Result.LoadFromStream(st, TBGRAReaderPNG.Create);
  finally
    st.Free;
  end;
end;

{ A PNG whose header says AW x AH and holds nothing more. }
function PngHeaderOnly(AW, AH: Cardinal): TBytes;
const
  Sig: array[0..15] of Byte = ($89, $50, $4E, $47, $0D, $0A, $1A, $0A, 0, 0, 0, 13, $49, $48,
    $44, $52);
var
  i: Integer;
begin
  Result := nil;
  SetLength(Result, 33);
  FillChar(Result[0], 33, 0);
  for i := 0 to 15 do Result[i] := Sig[i];
  Result[16] := AW shr 24; Result[17] := (AW shr 16) and $FF;
  Result[18] := (AW shr 8) and $FF; Result[19] := AW and $FF;
  Result[20] := AH shr 24; Result[21] := (AH shr 16) and $FF;
  Result[22] := (AH shr 8) and $FF; Result[23] := AH and $FF;
  Result[24] := 8;
  Result[25] := 6;
end;

procedure DumpDoc(const AWhat: string; D: TTyRichDocument);
var
  i: Integer;
begin
  WriteLn(AWhat, ': ', D.Text.ParaCount, ' paras, length ', D.Text.Length);
  for i := 0 to D.Text.ParaCount - 1 do WriteLn('  [', Shown(ParaText(D, i)), ']');
end;

{ ---- the suite ---- }

procedure TTyRichEditPasteTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FRich := TEditProbe.Create(nil);
  FRich.Controller := FCtl;
  FRich.Font.PixelsPerInch := 96;
  FRich.SetBounds(0, 0, 400, 300);
  FRich.OnChange := @Changed;
  FRich.OnSelectionChange := @SelChanged;
  FRich.ResetCounts;
  FRaiseOnChange := False;
  ResetEvents;
end;

procedure TTyRichEditPasteTest.TearDown;
begin
  FreeAndNil(FRich);
  FreeAndNil(FCtl);
end;

procedure TTyRichEditPasteTest.Changed(Sender: TObject);
begin
  Inc(FChanges);
  if FRaiseOnChange then raise Exception.Create('the test''s OnChange');
end;

procedure TTyRichEditPasteTest.SelChanged(Sender: TObject);
begin
  Inc(FSelChanges);
end;

procedure TTyRichEditPasteTest.ResetEvents;
begin
  FChanges := 0;
  FSelChanges := 0;
  if FRich <> nil then
  begin
    FRich.Refused := 0;
    FRich.LastReason := '';
    FRich.ClipReset;
  end;
end;

procedure TTyRichEditPasteTest.LoadBytes(const B: TBytes);
var
  st: TBytesStream;
begin
  st := TBytesStream.Create(B);
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
end;

procedure TTyRichEditPasteTest.LoadRtf(const S: RawByteString);
begin
  LoadBytes(RawBytes(S));
  FRich.FinishLoading;
  FRich.UpdateView;
  ResetEvents;
end;

procedure TTyRichEditPasteTest.SetText(const S: string);
begin
  FRich.Lines.Text := S;
  FRich.UpdateView;
  ResetEvents;
end;

procedure TTyRichEditPasteTest.Clip(const ARtf: RawByteString; const AText: string;
  const APicture: TBytes; AKind: TTyRichImageKind);
begin
  FRich.ClipRtf := ARtf;
  FRich.ClipText := AText;
  FRich.ClipPicture := APicture;
  FRich.ClipPictureKind := AKind;
  FRich.ClipHtml := '';
end;

function TTyRichEditPasteTest.Para(AIndex: Integer): RawByteString;
begin
  Result := ParaText(FRich.Document, AIndex);
end;

function TTyRichEditPasteTest.CharFormatAt(APos: TTyRichPos): TTyCharFormat;
var
  d: TTyRichDocument;
  p, i, k: Integer;
  runs: TTyRunArray;
begin
  d := FRich.Document;
  p := d.Text.ParaOfPos(APos);
  runs := d.RunsOf(p);
  k := 0;
  for i := 0 to High(runs) do
    if runs[i].Start <= APos - d.Text.ParaStart(p) then k := i;
  Result := d.Formats.CharFormat(runs[k].Format);
end;

function TTyRichEditPasteTest.ObjectAt(APos: TTyRichPos): TTyRichObject;
var
  d: TTyRichDocument;
  p, i: Integer;
  runs: TTyRunArray;
begin
  d := FRich.Document;
  p := d.Text.ParaOfPos(APos);
  runs := d.RunsOf(p);
  Result := nil;
  for i := 0 to High(runs) do
    if runs[i].Start = APos - d.Text.ParaStart(p) then Result := runs[i].Obj;
end;

procedure TTyRichEditPasteTest.PaintAll;
var
  bmp: TBitmap;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(FRich.Width, FRich.Height);
    FRich.PaintPart(bmp.Canvas, Rect(0, 0, FRich.Width, FRich.Height), True);
  finally
    bmp.Free;
  end;
end;

const
  ClipBold = '{' + BS + 'rtf1' + BS + 'ansi{' + BS + 'fonttbl{' + BS + 'f0 Times;}}' + BS +
    'f0' + BS + 'b RT}';

{ The brief's test: with RTF, a picture and text on the clipboard the RTF goes in (the others
  are not even read); without the RTF the picture; with text alone the text. And the
  application's "paste as": each flavour on request. }
procedure TTyRichEditPasteTest.TestPastePrefersRtfThenPictureThenText;
var
  pic: TBytes;
begin
  pic := MakePng(4, 3, BGRA(200, 10, 10, 255));
  SetText('ab');
  FRich.SelStart := 1;
  Clip(ClipBold, 'text', pic);
  FRich.PasteFromClipboard;
  AssertEquals('RTF first', 'aRTb', Para(0));
  AssertTrue('as RTF: bold', fsBold in CharFormatAt(1).Style);
  AssertEquals('the RTF read', 1, FRich.RtfReads);
  AssertEquals('the picture not read', 0, FRich.PictureReads);
  AssertEquals('the text not read', 0, FRich.TextReads);
  SetText('ab');
  FRich.SelStart := 1;
  Clip('', 'text', pic);
  FRich.PasteFromClipboard;
  AssertEquals('then the picture: one character', 3, FRich.Document.Text.Length);
  AssertTrue('a picture', ObjectAt(1) is TTyRichPicture);
  AssertEquals('the text not read', 0, FRich.TextReads);
  SetText('ab');
  FRich.SelStart := 1;
  Clip('', 'text');
  FRich.PasteFromClipboard;
  AssertEquals('then the text', 'atextb', Para(0));
  // paste as: the flavour asked for, nothing else
  SetText('ab');
  FRich.SelStart := 1;
  Clip(ClipBold, 'text', pic);
  FRich.PasteFromClipboard(rpaText);
  AssertEquals('as text', 'atextb', Para(0));
  AssertEquals('as text: the RTF not read', 0, FRich.RtfReads);
  SetText('ab');
  FRich.SelStart := 1;
  Clip(ClipBold, 'text', pic);
  FRich.PasteFromClipboard(rpaPicture);
  AssertTrue('as a picture', ObjectAt(1) is TTyRichPicture);
  SetText('ab');
  FRich.SelStart := 1;
  Clip('', 'text', pic);
  FRich.PasteFromClipboard(rpaRtf);
  AssertEquals('as RTF with none: nothing', 'ab', Para(0));
end;

{ A flavour that is there but cannot be used falls through to the next: RTF that is no RTF or
  holds nothing, a picture that does not decode. }
procedure TTyRichEditPasteTest.TestAFlavourThatCannotBeUsedFallsThrough;
var
  pic: TBytes;
begin
  pic := MakePng(2, 2, BGRA(0, 0, 255, 255));
  SetText('ab');
  FRich.SelStart := 1;
  Clip('no rtf at all', 'text', pic);
  FRich.PasteFromClipboard;
  AssertTrue('no RTF: the picture', ObjectAt(1) is TTyRichPicture);
  SetText('ab');
  FRich.SelStart := 1;
  Clip('{' + BS + 'rtf1' + BS + 'ansi{' + BS + 'fonttbl{' + BS + 'f0 Arial;}}}', 'text', nil);
  FRich.PasteFromClipboard;
  AssertEquals('RTF that holds nothing: the text', 'atextb', Para(0));
  SetText('ab');
  FRich.SelStart := 1;
  Clip('', 'text', RawBytes('not a picture'));
  FRich.PasteFromClipboard;
  AssertEquals('a picture that does not decode: the text', 'atextb', Para(0));
  SetText('ab');
  FRich.SelStart := 1;
  Clip('', 'text', MakePng(2, 2, BGRA(0, 0, 255, 255)), rikDib);
  FRich.PasteFromClipboard;
  AssertEquals('PNG bytes said to be a DIB: the text', 'atextb', Para(0));
  AssertEquals('nothing refused', 0, FRich.Refused);
end;

{ HTML is not a flavour the control takes: a clipboard with HTML and text pastes the text, one
  with HTML alone pastes nothing (and the menu says so). }
procedure TTyRichEditPasteTest.TestHtmlIsNoFlavourOfOurs;
var
  acts: ITyTextEditActions;
begin
  SetText('ab');
  FRich.SelStart := 1;
  Clip('', 'plain');
  FRich.ClipHtml := '<b>bold</b>';
  FRich.PasteFromClipboard;
  AssertEquals('the text', 'aplainb', Para(0));
  AssertEquals('the HTML never read', 0, FRich.HtmlReads);
  Clip('', '');
  FRich.ClipHtml := '<b>bold</b>';
  acts := FRich as ITyTextEditActions;
  AssertFalse('HTML alone: no paste', acts.TeCanPaste);
  AssertFalse('nor for code', FRich.CanPaste);
  FRich.PasteFromClipboard;
  AssertEquals('nothing', 'aplainb', Para(0));
end;

{ A paste over a selection is one undo step (never two), one OnChange and one
  OnSelectionChange, the caret behind what went in; undo puts the selection back as it was,
  redo leaves a plain caret behind the paste. }
procedure TTyRichEditPasteTest.TestAPasteIsOneStepAndUndoPutsTheSelectionBack;
var
  d: TTyRichDocument;
begin
  LoadRtf('{' + BS + 'rtf1' + BS + 'ansi abcd' + BS + 'par efgh' + BS + 'par}');
  d := FRich.Document;
  FRich.SelStart := 3;
  FRich.SelLength := -2;
  ResetEvents;
  Clip(ClipBold, '');
  AssertEquals('Ctrl+V taken', 0, FRich.KeyResult(VK_V, [ssCtrl]));
  AssertEquals('replaced', 'aRTd', Para(0));
  AssertEquals('one step', 1, d.UndoDepth);
  AssertEquals('named', rsRichUndoPaste, d.UndoDescription);
  AssertEquals('one change', 1, FChanges);
  AssertEquals('one selection change', 1, FSelChanges);
  AssertEquals('the caret behind it', Int64(3), FRich.CaretPos);
  AssertFalse('nothing selected', FRich.HasSelection);
  AssertTrue('modified', FRich.Modified);
  ResetEvents;
  FRich.Undo;
  AssertEquals('undone', 'abcd', Para(0));
  AssertEquals('the selection back: its start', Int64(1), FRich.SelStart);
  AssertEquals('its length', Int64(2), FRich.SelLength);
  AssertEquals('its caret where it was', Int64(1), FRich.CaretPos);
  FRich.Redo;
  AssertEquals('redone', 'aRTd', Para(0));
  AssertEquals('redo: a plain caret behind it', Int64(3), FRich.CaretPos);
  AssertFalse('redo: nothing selected', FRich.HasSelection);
  // several paragraphs selected and replaced: still one step
  FRich.SelStart := 2;
  FRich.SelLength := 5;
  Clip('', 'X' + LineEnding + 'Y');
  FRich.PasteFromClipboard;
  AssertEquals('two paragraphs', 'aRX', Para(0));
  AssertEquals('the second', 'Ygh', Para(1));
  AssertEquals('one more step', 2, d.UndoDepth);
  FRich.Undo;
  AssertEquals('undone: the first', 'aRTd', Para(0));
  AssertEquals('undone: the second', 'efgh', Para(1));
end;

{ A paste never merges with typing: typing before it, the paste, typing after it - three steps,
  each undone alone. }
procedure TTyRichEditPasteTest.TestAPasteIsNeverMergedWithTyping;
var
  d: TTyRichDocument;
begin
  SetText('');
  d := FRich.Document;
  FRich.Key8('q');
  Clip('', 'PP');
  FRich.PasteFromClipboard;
  FRich.Key8('z');
  FRich.Key8('z');
  AssertEquals('the text', 'qPPzz', Para(0));
  AssertEquals('three steps', 3, d.UndoDepth);
  FRich.Undo;
  AssertEquals('the typing after it alone', 'qPP', Para(0));
  FRich.Undo;
  AssertEquals('the paste alone', 'q', Para(0));
  // RTF too
  Clip(ClipBold, '');
  FRich.PasteFromClipboard;
  FRich.Key8('w');
  FRich.Undo;
  AssertEquals('typing after an RTF paste: a step of its own', 'qRT', Para(0));
end;

procedure TTyRichEditPasteTest.PasteWhileSaving(Sender: TObject; ADone, ATotal: Int64;
  var ACancel: Boolean);
var
  before: Integer;
begin
  Inc(FSaveCalls);
  if FSaveCalls > 1 then Exit;
  before := FRich.Refused;
  FRich.PasteFromClipboard;
  FSaveRefused := FRich.Refused - before;
end;

{ Every refusal: loading, after a cancelled load, while saving, in a row that holds a nested
  table, a selection across cells (R57), at a too-long paragraph's cut. EditRefused once with
  the control's reason, nothing changed, nothing raised. }
procedure TTyRichEditPasteTest.TestEveryRefusalOfAPaste;
var
  d: TTyRichDocument;
  len: Int64;
  k, n: Integer;
  c: TTyRichCell;
  st: TMemoryStream;
  sl: TStringList;
  rtf: RawByteString;

  procedure Refused(const AWhat, AReason: string);
  var
    l: Int64;
    depth: Integer;
  begin
    l := d.Text.Length;
    depth := d.UndoDepth;
    ResetEvents;
    Clip(ClipBold, 'text');
    FRich.PasteFromClipboard;
    AssertEquals(AWhat + ': refused once', 1, FRich.Refused);
    AssertEquals(AWhat + ': why', AReason, FRich.LastReason);
    AssertEquals(AWhat + ': nothing changed', l, d.Text.Length);
    AssertEquals(AWhat + ': no step', depth, d.UndoDepth);
    AssertEquals(AWhat + ': no change event', 0, FChanges);
    // the text too
    ResetEvents;
    Clip('', 'text');
    FRich.PasteFromClipboard;
    AssertEquals(AWhat + ': text refused once', 1, FRich.Refused);
    AssertEquals(AWhat + ': text, nothing changed', l, d.Text.Length);
  end;

begin
  // loading
  rtf := '{' + BS + 'rtf1' + BS + 'ansi ';
  for k := 0 to 2999 do rtf := rtf + 'Paragraph ' + IntToStr(k) + ' of the file.' + BS + 'par ';
  rtf := rtf + '}';
  FRich.Slices(2048, 2048);
  LoadBytes(RawBytes(rtf));
  d := FRich.Document;
  AssertTrue('loading', FRich.Loading);
  FRich.UpdateView;
  FRich.SelStart := 1;
  Refused('loading', rsRichEditRefusedLoading);
  FRich.CancelLoad;
  Refused('incomplete', rsRichEditRefusedIncomplete);
  // saving: from the save's progress handler
  sl := TStringList.Create;
  try
    for k := 0 to 39999 do sl.Add('A line of text that the save writes out: ' + IntToStr(k));
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
  d := FRich.Document;
  FRich.UpdateView;
  FRich.SelStart := 5;
  len := d.Text.Length;
  ResetEvents;
  Clip('', 'text');
  FRich.OnSaveProgress := @PasteWhileSaving;
  FSaveCalls := 0;
  st := TMemoryStream.Create;
  try
    FRich.SaveToStream(st, rfText);
  finally
    st.Free;
  end;
  FRich.OnSaveProgress := nil;
  AssertTrue('the save reported its progress', FSaveCalls > 0);
  AssertEquals('saving: refused once', 1, FSaveRefused);
  AssertEquals('saving: why', rsRichEditRefusedSaving, FRich.LastReason);
  AssertEquals('saving: nothing changed', len, d.Text.Length);
  // a row that holds a nested table
  LoadBytes(FileBytes(FixtureDir + 'word-table-merged.rtf'));
  FRich.FinishLoading;
  FRich.UpdateView;
  d := FRich.Document;
  n := 0;
  for k := 0 to d.Text.ParaCount - 1 do
  begin
    c := d.CellAt(k);
    if (c = nil) or not c.Row.HoldsNestedTable or (d.Text.ParaLength(k) < 2) then Continue;
    Inc(n);
    FRich.SelStart := d.Text.ParaStart(k) + 1;
    Refused(Format('a nested row, paragraph %d', [k]), rsRichEditRefusedFixedRow);
    AssertFalse('not modified', FRich.Modified);
    Break;
  end;
  AssertTrue('a nested row was met', n > 0);
  // across two cells
  LoadRtf('{' + BS + 'rtf1 ' + BS + 'trowd' + BS + 'cellx1000' + BS + 'cellx2000' + BS +
    'pard' + BS + 'intbl ab' + BS + 'cell cd' + BS + 'cell' + BS + 'row' + BS + 'pard z' + BS +
    'par}');
  d := FRich.Document;
  FRich.SelStart := 1;
  FRich.SelLength := 3;
  Refused('across cells', rsRichEditRefusedCells);
end;

{ ReadOnly: no paste by any door (the keys taken all the same), the clipboard not even read,
  the menu says no; nothing refused out loud. }
procedure TTyRichEditPasteTest.TestReadOnlyPastesNothing;
var
  acts: ITyTextEditActions;
begin
  SetText('ab');
  FRich.ReadOnly := True;
  FRich.SelStart := 1;
  Clip(ClipBold, 'text', MakePng(2, 2, BGRA(1, 2, 3, 255)));
  ResetEvents;
  Clip(ClipBold, 'text', MakePng(2, 2, BGRA(1, 2, 3, 255)));
  AssertEquals('Ctrl+V taken', 0, FRich.KeyResult(VK_V, [ssCtrl]));
  AssertEquals('Shift+Insert taken', 0, FRich.KeyResult(VK_INSERT, [ssShift]));
  FRich.PasteFromClipboard;
  acts := FRich as ITyTextEditActions;
  acts.TePaste;
  AssertFalse('the menu: no paste', acts.TeCanPaste);
  AssertFalse('CanPaste', FRich.CanPaste);
  AssertEquals('nothing', 'ab', Para(0));
  AssertEquals('nothing read', 0, FRich.RtfReads + FRich.PictureReads + FRich.TextReads);
  AssertEquals('no change', 0, FChanges);
  AssertEquals('nothing refused out loud', 0, FRich.Refused);
  FRich.ReadOnly := False;
  AssertTrue('editable: the menu offers it', acts.TeCanPaste);
end;

{ Each entry - Ctrl+V, Shift+Insert, PasteFromClipboard, the menu - ends an open composition
  first, as a press does (it goes in where it was shown), and then pastes after it. }
procedure TTyRichEditPasteTest.TestEachEntryEndsTheCompositionFirst;
var
  i: Integer;
const
  Names: array[0..3] of string = ('Ctrl+V', 'Shift+Insert', 'PasteFromClipboard', 'the menu');
begin
  for i := 0 to 3 do
  begin
    SetText('ab');
    FRich.SelStart := 1;
    AssertTrue(Names[i] + ': a composition', FRich.BeginComposition);
    FRich.UpdateComposition('ni');
    Clip('', 'XY');
    case i of
      0: AssertEquals('taken', 0, FRich.KeyResult(VK_V, [ssCtrl]));
      1: AssertEquals('taken', 0, FRich.KeyResult(VK_INSERT, [ssShift]));
      2: FRich.PasteFromClipboard;
      3: (FRich as ITyTextEditActions).TePaste;
    end;
    AssertFalse(Names[i] + ': the composition ended', FRich.Composing);
    AssertEquals(Names[i] + ': it went in first, the paste after it', 'aniXYb', Para(0));
    AssertEquals(Names[i] + ': the caret behind the paste', Int64(5), FRich.CaretPos);
    AssertEquals(Names[i] + ': two steps (the commit, the paste)', 2, FRich.Document.UndoDepth);
  end;
end;

{ RTF over selections: several paragraphs selected, everything selected. }
procedure TTyRichEditPasteTest.TestRtfJoinsReplacingSelections;
var
  d: TTyRichDocument;
const
  Two = '{' + BS + 'rtf1' + BS + 'ansi' + BS + 'pard' + BS + 'qc A' + BS + 'par' + BS + 'pard B}';
begin
  LoadRtf('{' + BS + 'rtf1' + BS + 'ansi' + BS + 'pard' + BS + 'qr abcd' + BS + 'par' + BS +
    'pard' + BS + 'qj efgh' + BS + 'par' + BS + 'pard ijkl' + BS + 'par}');
  d := FRich.Document;
  // "cd" .. "ef" replaced
  FRich.SelStart := 2;
  FRich.SelLength := 5;
  Clip(Two, '');
  FRich.PasteFromClipboard;
  AssertEquals('paragraphs', 3, d.Text.ParaCount);
  AssertEquals('the first', 'abA', Para(0));
  AssertTrue('in the first pasted one''s format', d.Formats.ParaFormat(d.ParaFormatOf(0)).Align = paraCenter);
  AssertEquals('the last', 'Bgh', Para(1));
  AssertTrue('in the format of the one it ends', d.Formats.ParaFormat(d.ParaFormatOf(1)).Align = paraJustify);
  AssertEquals('the caret behind B', d.Text.ParaStart(1) + 1, FRich.CaretPos);
  // everything
  FRich.SelectAll;
  FRich.PasteFromClipboard;
  AssertEquals('everything: paragraphs', 2, d.Text.ParaCount);
  AssertEquals('everything: A', 'A', Para(0));
  AssertEquals('everything: B', 'B', Para(1));
  FRich.Undo;
  AssertEquals('undone', 'abA', Para(0));
end;

{ Rows go in as rows at the caret in a plain paragraph; with the caret in a cell, or a
  selection in a table being replaced, as paragraphs - never a nested table. }
procedure TTyRichEditPasteTest.TestRowsAreRowsOutsideATableAndTextInOne;
var
  d: TTyRichDocument;
  i: Integer;
  c: TTyRichCell;
const
  Rows = '{' + BS + 'rtf1' + BS + 'ansi' + BS + 'trowd' + BS + 'cellx1000' + BS + 'cellx2000' +
    BS + 'pard' + BS + 'intbl r1' + BS + 'cell r2' + BS + 'cell' + BS + 'row}';
  Target = '{' + BS + 'rtf1' + BS + 'ansi plain' + BS + 'par' + BS + 'trowd' + BS + 'cellx1000' +
    BS + 'pard' + BS + 'intbl cell' + BS + 'cell' + BS + 'row' + BS + 'pard after' + BS + 'par}';
begin
  LoadRtf(Target);
  d := FRich.Document;
  FRich.SelStart := 2;
  Clip(Rows, '');
  FRich.PasteFromClipboard;
  AssertEquals('rows: split', 'pl', Para(0));
  AssertTrue('a row', (d.CellAt(1) <> nil) and (d.CellAt(2) <> nil) and (d.CellAt(2).Index = 1));
  AssertEquals('then the rest', 'ain', Para(3));
  AssertTrue('in no table', d.CellAt(3) = nil);
  // in a cell
  LoadRtf(Target);
  d := FRich.Document;
  c := d.CellAt(1);
  FRich.SelStart := d.Text.ParaStart(1) + 2;
  FRich.PasteFromClipboard;
  AssertEquals('in a cell: paragraphs', 5, d.Text.ParaCount);
  for i := 1 to 3 do AssertTrue(Format('paragraph %d in the cell', [i]), d.CellAt(i) = c);
  AssertEquals('in a cell: the text', 'cer1', Para(1));
  // a selection in a table replaced
  LoadRtf(Target);
  d := FRich.Document;
  c := d.CellAt(1);
  FRich.SelStart := d.Text.ParaStart(1) + 1;
  FRich.SelLength := 2;
  FRich.PasteFromClipboard;
  for i := 1 to 3 do AssertTrue(Format('a selection in a cell: paragraph %d in it', [i]), d.CellAt(i) = c);
  AssertEquals('one table, one row', 1, c.Table.RowCount);
end;

{ No document-level thing comes along (page, defaults); a run with no font of its own is
  named in the source's default font. }
procedure TTyRichEditPasteTest.TestTheSourcesDefaultFontAndNoDocumentLevelThing;
var
  d: TTyRichDocument;
  pw: Integer;
  df: TTyCharFormat;
begin
  LoadRtf('{' + BS + 'rtf1' + BS + 'ansi' + BS + 'deff0{' + BS + 'fonttbl{' + BS +
    'f0 Arial;}}' + BS + 'paperw12000 abc' + BS + 'par}');
  d := FRich.Document;
  pw := d.PaperWidth;
  df := d.DefaultCharFormat;
  FRich.SelStart := 1;
  Clip('{' + BS + 'rtf1' + BS + 'ansi' + BS + 'deff0{' + BS + 'fonttbl{' + BS +
    'f0 Courier New;}}' + BS + 'paperw3000' + BS + 'margl10{' + BS + 'info{' + BS +
    'title X}}xy}', '');
  FRich.PasteFromClipboard;
  AssertEquals('pasted', 'axybc', Para(0));
  AssertEquals('the page stays', pw, d.PaperWidth);
  AssertTrue('the defaults stay', df.Equals(d.DefaultCharFormat));
  AssertEquals('in the source''s font', 'Courier New', CharFormatAt(1).FontName);
  AssertEquals('the text after in its own', 'Arial', CharFormatAt(3).FontName);
end;

{ Every sample's ranges - all of it, a third, paragraphs with and without their separator,
  across two - copied by the range writer and pasted into an empty document and into the
  middle of a paragraph of another, read back as the range. }
procedure TTyRichEditPasteTest.TestEveryFixturesRangesPasteBackAsTheRange;
var
  sr: TSearchRec;
  a: TTyRichDocument;
  t: TTyRichText;
  files, q, n, pastes: Integer;
  ps, pl, L: TTyRichPos;

  procedure Check(const AWhat: string; AFrom, ALen: TTyRichPos);
  var
    rtf: TBytes;
    b: TTyRichDocument;
    dd: string;
  begin
    try
      rtf := RangeOut(a, AFrom, ALen);
    except
      // a range the writer refuses: a changed row that holds a nested table (9b's rule)
      on ETyRichRtfWrite do Exit;
    end;
    // into an empty document
    b := TTyRichDocument.Create;
    try
      if not PasteInto(b, 0, rtf) then Exit;
      dd := PasteDiff(a, AFrom, ALen, b, 0, 0);
      if dd <> '' then Fail(Format('%s [%d +%d] into an empty document: %s', [AWhat, AFrom, ALen, dd]));
      Inc(pastes);
    finally
      b.Free;
    end;
    // into the middle of a paragraph
    b := LoadDoc(RawBytes('{' + BS + 'rtf1' + BS + 'ansi before' + BS + 'par 0123456789' + BS +
      'par after' + BS + 'par}'), True);
    try
      PasteInto(b, b.Text.ParaStart(1) + 5, rtf);
      dd := PasteDiff(a, AFrom, ALen, b, 1, 5);
      if dd <> '' then Fail(Format('%s [%d +%d] into a paragraph: %s', [AWhat, AFrom, ALen, dd]));
      AssertEquals(AWhat + ': the paragraph before stays', 'before', ParaText(b, 0));
    finally
      b.Free;
    end;
  end;

begin
  files := 0;
  pastes := 0;
  if FindFirst(FixtureDir + '*.rtf', faAnyFile, sr) = 0 then
  try
    repeat
      a := LoadDoc(FileBytes(FixtureDir + sr.Name), False);
      try
        t := a.Text;
        L := t.Length;
        Check(sr.Name + ' all', 0, L);
        Check(sr.Name + ' a third', L div 3, L div 3);
        n := t.ParaCount;
        if n > 12 then n := 12;
        for q := 0 to n - 1 do
        begin
          ps := t.ParaStart(q);
          pl := t.ParaLength(q);
          if pl >= 1 then Check(Format('%s paragraph %d without its separator', [sr.Name, q]), ps, pl);
          if q < t.ParaCount - 1 then
          begin
            Check(Format('%s paragraph %d with its separator', [sr.Name, q]), ps, pl + 1);
            Check(Format('%s across %d and %d', [sr.Name, q, q + 1]), ps + pl div 2,
              pl - pl div 2 + 1 + t.ParaLength(q + 1) div 2);
          end;
        end;
      finally
        a.Free;
      end;
      Inc(files);
    until FindNext(sr) <> 0;
  finally
    FindClose(sr);
  end;
  AssertTrue('the samples', files >= 20);
  AssertTrue(Format('pastes checked (%d)', [pastes]), pastes > 100);
end;

{ A whole sample pasted into an empty new document and saved reads back as the sample's
  content: its paragraphs, their text, formats and cells. }
procedure TTyRichEditPasteTest.TestAWholeFixturePastedAndSavedReadsBack;
var
  sr: TSearchRec;
  a, b, c: TTyRichDocument;
  files, k, last: Integer;
  dd: string;
begin
  files := 0;
  if FindFirst(FixtureDir + '*.rtf', faAnyFile, sr) = 0 then
  try
    repeat
      a := LoadDoc(FileBytes(FixtureDir + sr.Name), True);
      b := TTyRichDocument.Create;
      c := nil;
      try
        try
          PasteInto(b, 0, RangeOut(a, 0, a.Text.Length));
        except
          on ETyRichRtfWrite do Continue;
        end;
        c := LoadDoc(SaveOut(b), True);
        // (the last paragraph of the paste is the new document's own one)
        last := a.Text.ParaCount - 1;
        dd := PasteDiff(a, 0, a.Text.Length, c, 0, 0, True);
        if dd <> '' then Fail(sr.Name + ': ' + dd);
        AssertTrue(sr.Name + ': paragraphs', c.Text.ParaCount >= last + 1);
        for k := 0 to last - 1 do
          AssertEquals(Format('%s: paragraph %d', [sr.Name, k]), Shown(ParaText(a, k)),
            Shown(ParaText(c, k)));
        Inc(files);
      finally
        c.Free;
        b.Free;
        a.Free;
      end;
    until FindNext(sr) <> 0;
  finally
    FindClose(sr);
  end;
  AssertTrue('the samples', files >= 20);
end;

{ RTF is whatever another program put there: no paragraphs, only a header, an unterminated
  group, megabytes of one paragraph, a picture with absurd dimensions. Each ends in a clean
  paste of what could be read or in the next flavour; nothing is raised. }
procedure TTyRichEditPasteTest.TestUntrustedRtfFromTheClipboard;
var
  s: RawByteString;
begin
  SetText('ab');
  FRich.SelStart := 1;
  Clip('{' + BS + 'rtf1}', 'T');
  FRich.PasteFromClipboard;
  AssertEquals('no paragraphs: the text', 'aTb', Para(0));
  SetText('ab');
  FRich.SelStart := 1;
  Clip('{' + BS + 'rtf1' + BS + 'ansi{' + BS + 'colortbl;' + BS + 'red1;}', 'T');
  FRich.PasteFromClipboard;
  AssertEquals('only a header: the text', 'aTb', Para(0));
  SetText('ab');
  FRich.SelStart := 1;
  Clip('{' + BS + 'rtf1 xy{' + BS + 'b z', 'T');
  FRich.PasteFromClipboard;
  AssertEquals('an unterminated group: what was read', 'axyzb', Para(0));
  SetText('ab');
  FRich.SelStart := 1;
  SetLength(s, 2 * 1024 * 1024);
  FillChar(s[1], Length(s), 'm');
  Clip('{' + BS + 'rtf1 ' + s + '}', 'T');
  FRich.PasteFromClipboard;
  AssertEquals('megabytes of one paragraph: one paragraph', 1, FRich.Document.Text.ParaCount);
  AssertEquals('all of it', Int64(2 + Length(s)), FRich.Document.Text.Length);
  SetText('ab');
  FRich.SelStart := 1;
  Clip('{' + BS + 'rtf1 x{' + BS + 'pict' + BS + 'pngblip' + BS + 'picwgoal2147483647' + BS +
    'pichgoal2147483647 89504e47}y}', 'T');
  FRich.PasteFromClipboard;
  AssertEquals('an absurd picture: pasted as read', 5, FRich.Document.Text.Length);
  PaintAll;
  AssertEquals('nothing refused', 0, FRich.Refused);
end;

{ A DIB becomes one picture stored as PNG, its size the image's at 96 dpi (or the DIB's own
  resolution), its alpha kept; one with no alpha at all is opaque. }
procedure TTyRichEditPasteTest.TestAPictureFromADib;
var
  p: TTyRichPicture;
  img: TBGRABitmap;
begin
  SetText('ab');
  FRich.SelStart := 1;
  Clip('', '', MakeDib(4, 3, 10, 20, 30, 128), rikDib);
  FRich.PasteFromClipboard;
  AssertEquals('one character', 3, FRich.Document.Text.Length);
  p := ObjectAt(1) as TTyRichPicture;
  AssertTrue('stored as PNG', p.PictureFormat = rpfPng);
  AssertEquals('4 px at 96 dpi', 60, p.WidthTwips);
  AssertEquals('3 px at 96 dpi', 45, p.HeightTwips);
  img := DecodePng(p.Data);
  try
    AssertEquals('its width', 4, img.Width);
    AssertEquals('its height', 3, img.Height);
    AssertEquals('alpha kept', 128, img.GetPixel(1, 1).alpha);
  finally
    img.Free;
  end;
  AssertEquals('the caret behind it', Int64(2), FRich.CaretPos);
  // no alpha in any pixel: opaque
  SetText('ab');
  FRich.SelStart := 1;
  Clip('', '', MakeDib(2, 2, 10, 20, 30, 0), rikDib);
  FRich.PasteFromClipboard;
  img := DecodePng((ObjectAt(1) as TTyRichPicture).Data);
  try
    AssertEquals('opaque', 255, img.GetPixel(0, 0).alpha);
  finally
    img.Free;
  end;
  // its own resolution: 192 dpi (7559 pixels a metre)
  SetText('ab');
  FRich.SelStart := 1;
  Clip('', '', MakeDib(4, 4, 1, 2, 3, 255, 7559), rikDib);
  FRich.PasteFromClipboard;
  AssertEquals('at 192 dpi', 30, (ObjectAt(1) as TTyRichPicture).WidthTwips);
end;

{ A PNG goes in with its bytes as they are; the picture saves as \pngblip and reads back. }
procedure TTyRichEditPasteTest.TestAPngIsKeptAndAPictureIsSavedAndReadBack;
var
  png: TBytes;
  p: TTyRichPicture;
  st: TBytesStream;
  b: TTyRichDocument;
  runs: TTyRunArray;
  i: Integer;
  found: Boolean;
begin
  png := MakePng(5, 2, BGRA(9, 8, 7, 100));
  LoadRtf('{' + BS + 'rtf1' + BS + 'ansi ab' + BS + 'par}');
  FRich.SelStart := 1;
  Clip('', '', png);
  FRich.PasteFromClipboard;
  p := ObjectAt(1) as TTyRichPicture;
  AssertTrue('PNG', p.PictureFormat = rpfPng);
  AssertTrue('its bytes kept', SameRaw(StrOfBytes(png), StrOfBytes(p.Data)));
  AssertEquals('5 px', 75, p.WidthTwips);
  PaintAll;
  st := TBytesStream.Create;
  try
    FRich.SaveToStream(st, rfRtf);
    AssertTrue('pngblip', Pos('pngblip', StrOfBytes(Copy(st.Bytes, 0, st.Size))) > 0);
    b := LoadDoc(Copy(st.Bytes, 0, st.Size), True);
  finally
    st.Free;
  end;
  try
    runs := b.RunsOf(0);
    found := False;
    for i := 0 to High(runs) do
      if runs[i].Obj is TTyRichPicture then
      begin
        found := True;
        AssertTrue('read back: its bytes', SameRaw(StrOfBytes(png),
          StrOfBytes(TTyRichPicture(runs[i].Obj).Data)));
        AssertEquals('read back: its width', 75, TTyRichPicture(runs[i].Obj).WidthTwips);
      end;
    AssertTrue('read back: a picture', found);
  finally
    b.Free;
  end;
end;

{ Wider than the paragraph's room: scaled down to it, the ratio kept. Larger than the bound
  (CRichPictureMaxPixels): refused, told once, nothing changed. }
procedure TTyRichEditPasteTest.TestAPictureWiderThanTheTextIsScaledAndTooLargeIsRefused;
var
  p: TTyRichPicture;
begin
  SetText('ab');
  FRich.SelStart := 1;
  Clip('', '', MakeDib(2000, 1000, 1, 2, 3, 255), rikDib);
  FRich.PasteFromClipboard;
  p := ObjectAt(1) as TTyRichPicture;
  AssertTrue(Format('narrower than the image (%d)', [p.WidthTwips]), p.WidthTwips < 2000 * 15);
  AssertTrue(Format('within the text (%d twips, the control 400 px)', [p.WidthTwips]),
    p.WidthTwips <= 400 * 15);
  AssertTrue(Format('the ratio kept (%d x %d)', [p.WidthTwips, p.HeightTwips]),
    Abs(p.HeightTwips * 2 - p.WidthTwips) <= 2);
  SetText('ab');
  FRich.SelStart := 1;
  ResetEvents;
  Clip('', 'text', PngHeaderOnly(10000, 10000));
  FRich.PasteFromClipboard;
  AssertEquals('too large: refused once', 1, FRich.Refused);
  AssertEquals('why', rsRichEditRefusedPicture, FRich.LastReason);
  AssertEquals('nothing changed', 'ab', Para(0));
  AssertEquals('no change event', 0, FChanges);
end;

{ Plain text: CR LF, CR, LF, U+2028, U+2029 make paragraphs in the caret paragraph's format;
  U+000B stays a line break (a paragraph in a plain-text document); tabs stay; control
  characters go; the typing format at the caret; a last line without a line end inline. }
procedure TTyRichEditPasteTest.TestPlainTextLinesAndCharacters;
var
  d: TTyRichDocument;
  i: Integer;
begin
  LoadRtf('{' + BS + 'rtf1' + BS + 'ansi' + BS + 'pard' + BS + 'qc ab' + BS + 'b cd' + BS +
    'par}');
  d := FRich.Document;
  FRich.SelStart := 3;
  Clip('', 'L1'#13#10'L2'#13'L3'#10'L4' + U($2028) + 'L5' + U($2029) + 'L6'#11'x'#9'y'#1#127 +
    U($85) + 'z');
  FRich.PasteFromClipboard;
  AssertEquals('paragraphs', 6, d.Text.ParaCount);
  AssertEquals('the first joins the text before', 'abcL1', Para(0));
  AssertEquals('L2', 'L2', Para(1));
  AssertEquals('L5', 'L5', Para(4));
  AssertEquals('the last inline, the text after it follows', 'L6'#11'x'#9'yzd', Para(5));
  for i := 0 to 5 do
    AssertTrue(Format('paragraph %d centred', [i]), d.Formats.ParaFormat(d.ParaFormatOf(i)).Align = paraCenter);
  AssertTrue('in the typing format (bold)', fsBold in CharFormatAt(d.Text.ParaStart(2)).Style);
  AssertEquals('the caret behind it', d.Text.ParaStart(5) + 7, FRich.CaretPos);
  AssertEquals('one step', 1, d.UndoDepth);
  // a plain-text document: U+000B a paragraph
  SetText('ab');
  FRich.SelStart := 1;
  Clip('', 'x'#11'y');
  FRich.PasteFromClipboard;
  AssertEquals('a text document: two paragraphs', 2, FRich.Document.Text.ParaCount);
  AssertEquals('x', 'ax', Para(0));
  AssertEquals('y', 'yb', Para(1));
end;

{ Bytes that are not UTF-8 are read as the text reader reads them (the ANSI code page), never
  refused half way; in a cell the lines are paragraphs of that cell. }
procedure TTyRichEditPasteTest.TestPlainTextThatIsNotUtf8AndInACell;
var
  d, ref: TTyRichDocument;
  raw: RawByteString;
  st: TBytesStream;
  c: TTyRichCell;
  i: Integer;
begin
  raw := 'abc'#$C4#$E3'd'#$E9;
  ref := TTyRichDocument.Create;
  st := TBytesStream.Create(RawBytes(raw));
  try
    TyRichLoadText(ref, st);
    SetText('[]');
    FRich.SelStart := 1;
    ResetEvents;
    Clip('', raw);
    FRich.PasteFromClipboard;
    AssertEquals('nothing refused', 0, FRich.Refused);
    AssertEquals('as the text reader reads it', Shown('[' + ParaText(ref, 0) + ']'), Shown(Para(0)));
  finally
    st.Free;
    ref.Free;
  end;
  LoadRtf('{' + BS + 'rtf1 ' + BS + 'trowd' + BS + 'cellx1000' + BS + 'pard' + BS + 'intbl xy' +
    BS + 'cell' + BS + 'row' + BS + 'pard z' + BS + 'par}');
  d := FRich.Document;
  c := d.CellAt(0);
  FRich.SelStart := 1;
  Clip('', 'one'#9'two'#13#10'three');
  FRich.PasteFromClipboard;
  AssertEquals('in a cell: paragraphs', 3, d.Text.ParaCount);
  for i := 0 to 1 do AssertTrue(Format('paragraph %d in the cell', [i]), d.CellAt(i) = c);
  AssertEquals('no cells from tabs', 'xone'#9'two', Para(0));
  AssertEquals('one row still', 1, c.Table.RowCount);
end;

{ CanPaste (the menu asks on every popup) reads nothing: only which flavours are there. }
procedure TTyRichEditPasteTest.TestCanPasteReadsNothing;
var
  s: string;
begin
  SetText('ab');
  SetLength(s, 8 * 1024 * 1024);
  FillChar(s[1], Length(s), 'q');
  Clip('{' + BS + 'rtf1 ' + s + '}', s, MakePng(2, 2, BGRA(1, 1, 1, 255)));
  ResetEvents;
  AssertTrue('there is something', FRich.CanPaste);
  AssertTrue('the menu too', (FRich as ITyTextEditActions).TeCanPaste);
  AssertEquals('nothing read', 0, FRich.RtfReads + FRich.PictureReads + FRich.TextReads);
  AssertTrue('only asked', FRich.FlavourAsks >= 2);
  Clip('', '');
  AssertFalse('an empty clipboard', FRich.CanPaste);
end;

{ A one-line paste in the middle of 2,000,000 lines lays out and paints what a typed character
  does: that paragraph, a few hundred tree nodes. Text and RTF alike. }
procedure TTyRichEditPasteTest.TestAOneLinePasteInALargeDocumentTouchesOneParagraph;
var
  t: TTyRichText;
  p: Integer;
  visits, n: Int64;
begin
  LoadBytes(BigText);
  t := FRich.Document.Text;
  AssertEquals('all the lines', BigLines, t.ParaCount);
  FRich.UpdateView;
  FRich.ScrollY := t.TotalHeight div 2;
  FRich.UpdateView;
  p := FRich.TopParagraph + 3;
  FRich.SelStart := t.ParaStart(p) + 2;
  PaintAll;
  FRich.ResetCounts;
  visits := t.NodeVisits;
  Clip('', 'pasted');
  FRich.PasteFromClipboard;
  AssertEquals('pasted', 'Lipastedne ' + IntToStr(p + 1), Para(p));
  AssertEquals(Format('one paragraph laid out (%d)', [FRich.LaidParas]), 1, FRich.LaidParas);
  AssertEquals('that one', p, FRich.LaidMin);
  n := t.NodeVisits - visits;
  AssertTrue(Format('%d tree nodes entered', [n]), n <= 400);
  PaintAll;
  AssertTrue(Format('%d blocks painted', [FRich.BlockPaints]), FRich.BlockPaints <= 3);
  AssertEquals('no frame', 0, FRich.FramePaints);
  // RTF, inline
  FRich.ResetCounts;
  visits := t.NodeVisits;
  Clip(ClipBold, '');
  FRich.PasteFromClipboard;
  AssertEquals('RTF: one paragraph laid out', 1, FRich.LaidParas);
  AssertTrue(Format('RTF: %d tree nodes', [t.NodeVisits - visits]), t.NodeVisits - visits <= 400);
  PaintAll;
  AssertTrue(Format('RTF: %d blocks painted', [FRich.BlockPaints]), FRich.BlockPaints <= 3);
  WriteLn(Format('TTyRichEditPasteTest: a one-line paste in %d lines: %d tree nodes', [BigLines, n]));
end;

{ Over CopyWaitChars bytes pasted: the wait cursor meanwhile, put back also when the paste
  fails (an OnChange that raises); under it none. }
procedure TTyRichEditPasteTest.TestTheWaitCursorOverTheThreshold;
var
  raised: Boolean;
begin
  SetText('ab');
  FRich.SetCopyWait(10);
  Clip('', 'short');
  FRich.PasteFromClipboard;
  AssertEquals('under: none', 0, FRich.Waits);
  Clip('', 'a text over ten');
  FRich.PasteFromClipboard;
  AssertEquals('over: one', 1, FRich.Waits);
  AssertEquals('put back', 1, FRich.WaitEnds);
  Clip(ClipBold + '                    ', '');
  FRich.PasteFromClipboard;
  AssertEquals('RTF over: one more', 2, FRich.Waits);
  AssertEquals('RTF: put back', 2, FRich.WaitEnds);
  FRaiseOnChange := True;
  raised := False;
  Clip('', 'a text over ten again');
  try
    FRich.PasteFromClipboard;
  except
    raised := True;
  end;
  FRaiseOnChange := False;
  AssertTrue('(the paste failed)', raised);
  AssertEquals('failed: one more', 3, FRich.Waits);
  AssertEquals('failed: put back', 3, FRich.WaitEnds);
end;

initialization
  RegisterTest(TTyRichEditPasteTest);

end.
