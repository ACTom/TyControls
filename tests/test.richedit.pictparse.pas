unit test.richedit.pictparse;

{ A picture read from a file the document keeps is not converted when its paragraph is
  parsed: the parse notes where the picture's data lies in the file's bytes and how long it
  is, copies nothing and turns no hex digit into a byte (the load's PictureBytesConverted and
  PictureBytesCopied stay 0), so the parse costs what finding the group's end costs, whatever
  the picture's size. Its bytes are made when they are asked for (MakeImageData, the decode for
  display, a save of a resized picture) and are those a parser that converts them as it
  reads gives - read lazily, whole, or as a fragment -, for PNG, JPEG, a metafile and \bin.
  Open and save stays the file; an edit beside a picture writes its group as the file
  has it; a picture that leaves its document (a clone, the filter between two documents) owns
  its bytes and outlives the first document; resize, replace and undo keep the file's bytes. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.Commands,
  tyControls.RichEdit.RtfRead, tyControls.RichEdit.RtfWrite, tyControls.RichEdit.Find;

type
  TTyRichPictureParseTest = class(TTestCase)
  published
    procedure TestAPictureParagraphIsParsedWithoutConvertingItsData;
    procedure TestThePicturesBytesAreTheSameReadLazilyWholeOrAsAFragment;
    procedure TestOpenAndSaveWithPicturesIsTheFile;
    procedure TestAnEditBesideAPictureWritesItsGroupAsTheFileHasIt;
    procedure TestAPictureThatLeavesItsDocumentOwnsItsBytes;
    procedure TestResizeReplaceAndUndoKeepTheFilesBytes;
    procedure TestLazyAndWholeAgreeOnEveryFileWithPictures;
    procedure TestADecodeMakesAPicturesBytesOnce;
    procedure TestABinaryPictureResizedIsSavedWithItsBytes;
    procedure TestWhatMayShowWithoutReadingTheBytes;
    procedure TestAGroupThatEndsInAWordIsEndedBeforeTheTextAfterIt;
  end;

implementation

uses
  Types, Graphics, BGRABitmap, BGRABitmapTypes, tyControls.Controller, tyControls.RichEdit;

type
  // the control's paint into a bitmap, as a window's (pictures deferred), and its idle step
  TPictRich = class(TTyRichEdit)
  public
    procedure PaintInto(ABitmap: TBitmap);
    function Step: Boolean;
  end;

procedure TPictRich.PaintInto(ABitmap: TBitmap);
begin
  PaintArea(ABitmap.Canvas, Rect(0, 0, Width, Height), Rect(0, 0, Width, Height), 96, True);
end;

function TPictRich.Step: Boolean;
begin
  Result := StepBackground;
end;

const
  BS = #92;

{ ---- helpers ---- }

function RepoRoot: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim;
end;

function Fixture(const AName: string): TBytes;
var
  f: TFileStream;
begin
  Result := nil;
  f := TFileStream.Create(RepoRoot + 'tests' + PathDelim + 'fixtures' + PathDelim + 'rtf' +
    PathDelim + AName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, f.Size);
    if f.Size > 0 then f.ReadBuffer(Result[0], f.Size);
  finally
    f.Free;
  end;
end;

// RTF written with | for each backslash.
function Bar(const S: RawByteString): RawByteString;
var
  i: Integer;
begin
  Result := S;
  UniqueString(Result);
  for i := 1 to Length(Result) do
    if Result[i] = '|' then Result[i] := BS;
end;

function BytesOf(const S: RawByteString): TBytes;
begin
  Result := nil;
  SetLength(Result, Length(S));
  if S <> '' then Move(S[1], Result[0], Length(S));
end;

function StrOf(const B: TBytes): RawByteString;
begin
  Result := '';
  SetLength(Result, Length(B));
  if Length(B) > 0 then Move(B[0], Result[1], Length(B));
end;

function SameBytes(const A, B: TBytes): Boolean;
begin
  Result := (Length(A) = Length(B)) and ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A)));
end;

function Math_Max1(A: Integer): Integer;
begin
  if A < 1 then Result := 1 else Result := A;
end;

{ AData as hex digits: APerLine bytes a line (CRLF; 0: one line), upper or lower case. }
function HexOf(const AData: TBytes; APerLine: Integer; AUpper: Boolean): RawByteString;
const
  L: array[0..15] of AnsiChar = '0123456789abcdef';
  U: array[0..15] of AnsiChar = '0123456789ABCDEF';
var
  i, o: Integer;
begin
  Result := '';
  SetLength(Result, Length(AData) * 2 + (Length(AData) div Math_Max1(APerLine) + 1) * 2);
  o := 1;
  for i := 0 to High(AData) do
  begin
    if (APerLine > 0) and (i > 0) and (i mod APerLine = 0) then
    begin
      Result[o] := #13;
      Result[o + 1] := #10;
      Inc(o, 2);
    end;
    if AUpper then
    begin
      Result[o] := U[AData[i] shr 4];
      Result[o + 1] := U[AData[i] and 15];
    end
    else
    begin
      Result[o] := L[AData[i] shr 4];
      Result[o + 1] := L[AData[i] and 15];
    end;
    Inc(o, 2);
  end;
  SetLength(Result, o - 1);
end;

{ A PNG whose pixels do not compress: about AW x AH x 4 bytes. }
function NoisePng(AW, AH: Integer; ASeed: Cardinal): TBytes;
var
  b: TBGRABitmap;
  st: TBytesStream;
  p: PBGRAPixel;
  i: Integer;
begin
  b := TBGRABitmap.Create(AW, AH);
  st := TBytesStream.Create;
  try
    p := b.Data;
    for i := 0 to AW * AH - 1 do
    begin
      ASeed := ASeed xor (ASeed shl 13);
      ASeed := ASeed xor (ASeed shr 17);
      ASeed := ASeed xor (ASeed shl 5);
      p^.red := ASeed and $FF;
      p^.green := (ASeed shr 8) and $FF;
      p^.blue := (ASeed shr 16) and $FF;
      p^.alpha := 255;
      Inc(p);
    end;
    b.InvalidateBitmap;
    b.SaveToStreamAs(st, ifPng);
    Result := Copy(st.Bytes, 0, st.Size);
  finally
    st.Free;
    b.Free;
  end;
end;

function JpegOf(AW, AH: Integer): TBytes;
var
  b: TBGRABitmap;
  st: TBytesStream;
  x, y: Integer;
begin
  b := TBGRABitmap.Create(AW, AH);
  st := TBytesStream.Create;
  try
    for y := 0 to AH - 1 do
      for x := 0 to AW - 1 do
        b.SetPixel(x, y, BGRA(x * 255 div AW, y * 255 div AH, 90, 255));
    b.SaveToStreamAs(st, ifJpeg);
    Result := Copy(st.Bytes, 0, st.Size);
  finally
    st.Free;
    b.Free;
  end;
end;

procedure Put16(var B: TBytes; AValue: Integer);
var
  n: Integer;
begin
  n := Length(B);
  SetLength(B, n + 2);
  B[n] := Byte(AValue);
  B[n + 1] := Byte(AValue shr 8);
end;

procedure Put32(var B: TBytes; AValue: Cardinal);
begin
  Put16(B, Integer(AValue and $FFFF));
  Put16(B, Integer(AValue shr 16));
end;

{ A metafile whose one drawing is a 2 x 2 bitmap (META_STRETCHDIB): one the layout shows as
  that bitmap. }
function SingleBitmapWmf: TBytes;
var
  params: TBytes;
  i: Integer;
begin
  params := nil;
  Put32(params, $00CC0020);                 // SRCCOPY
  Put16(params, 0);
  Put16(params, 2);
  Put16(params, 2);
  Put16(params, 0);
  Put16(params, 0);
  for i := 1 to 4 do Put16(params, 2);
  Put32(params, 40);
  Put32(params, 2);
  Put32(params, 2);
  Put16(params, 1);
  Put16(params, 24);
  for i := 1 to 6 do Put32(params, 0);
  for i := 1 to 8 do Put16(params, $7F3F);
  Result := nil;
  Put16(Result, 1);
  Put16(Result, 9);
  Put16(Result, $0300);
  Put32(Result, 0);
  Put16(Result, 0);
  Put32(Result, 0);
  Put16(Result, 0);
  Put32(Result, Cardinal(3 + Length(params) div 2));
  Put16(Result, $0F43);
  i := Length(Result);
  SetLength(Result, i + Length(params));
  Move(params[0], Result[i], Length(params));
  Put32(Result, 3);
  Put16(Result, 0);
end;

const
  CHead = '{|rtf1|ansi|ansicpg936|deff0{|fonttbl{|f0|fnil|fcharset134 SimSun;}' +
    '{|f1|fswiss|fcharset0 Arial;}}' + #13#10 + '|viewkind4|uc1|pard|f0|fs24 ';

{ A document: three paragraphs of Chinese and Latin text, the paragraph that holds AGroup
  (between "图片" and "after"), two more paragraphs. AGroup is written as it is. }
function DocWith(const AGroup: RawByteString): TBytes;
var
  s: RawByteString;
  i: Integer;
begin
  s := Bar(CHead);
  for i := 1 to 3 do
    s := s + Bar('|u20013?|u25991? before ' + IntToStr(i) + ' |b bold|b0  words|par') + #13#10;
  s := s + Bar('|u22270?|u29255? ') + AGroup + Bar(' after the picture|par') + #13#10;
  for i := 1 to 2 do
    s := s + Bar('|f1 Latin line ' + IntToStr(i) + ' |f0|u20013? end|par') + #13#10;
  s := s + '}' + #13#10;
  Result := BytesOf(s);
end;

function PictGroup(const AWords: RawByteString; const AData: RawByteString): RawByteString;
begin
  Result := Bar('{|pict' + AWords + '|picw40|pich30|picwgoal600|pichgoal450 ') + AData + '}';
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

function ReadFragment(const ABytes: TBytes): TTyRichDocument;
var
  ends: Boolean;
begin
  Result := TyRichReadRtfFragment(ABytes, ends);
end;

function SaveOf(ADoc: TTyRichDocument): TBytes;
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

{ The first picture of the document (its paragraphs read; call inside a read scope), and the
  paragraph it is in; nil, -1: none. }
function FirstPicture(ADoc: TTyRichDocument; out APara: Integer): TTyRichPicture;
var
  k, j: Integer;
  runs: TTyRunArray;
begin
  for k := 0 to ADoc.Text.ParaCount - 1 do
  begin
    runs := ADoc.RunsOf(k);
    for j := 0 to High(runs) do
      if runs[j].Obj is TTyRichPicture then
      begin
        APara := k;
        Exit(TTyRichPicture(runs[j].Obj));
      end;
  end;
  APara := -1;
  Result := nil;
end;

// The character position of the picture in paragraph APara.
function PicturePos(ADoc: TTyRichDocument; APara: Integer): TTyRichPos;
var
  runs: TTyRunArray;
  j: Integer;
begin
  runs := ADoc.RunsOf(APara);
  for j := 0 to High(runs) do
    if runs[j].Obj is TTyRichPicture then Exit(ADoc.Text.ParaStart(APara) + runs[j].Start);
  Result := -1;
end;

{ The picture a parser whose bytes no document keeps reads from ABytes - one that converts
  them as it reads, as every parse did before -; its last picture (the one a paragraph gets:
  of Word's pair, the pair). The caller releases it. }
procedure AssertFalseHelper(A: Boolean);
begin
  if A then raise EAssertionFailedError.Create('a parser of its own keeps no file');
end;

function ConvertingRead(const ABytes: TBytes): TTyRichPicture;
var
  d: TTyRichDocument;
  p: TTyRtfParser;
  objs: TFPList;
  i: Integer;
begin
  Result := nil;
  objs := nil;
  d := TTyRichDocument.Create;
  try
    p := TTyRtfParser.Create(ABytes, d.Formats);
    try
      AssertFalseHelper(p.MarksInFile);
      p.Parse;
      objs := p.TakeObjects;
    finally
      p.Free;
    end;
    for i := 0 to objs.Count - 1 do
      if TObject(objs[i]) is TTyRichPicture then Result := TTyRichPicture(objs[i]);
    if Result <> nil then Result.AddRef;
    for i := 0 to objs.Count - 1 do TTyRichObject(objs[i]).Release;
  finally
    objs.Free;
    d.Free;
  end;
end;

procedure CheckSamePicture(const AMsg: string; A, B: TTyRichPicture);
var
  fa, fb: TTyRichPictureFormat;
  sa, sb, ca, cb: Integer;
  da, db: Boolean;
begin
  if (A = nil) or (B = nil) then
    raise EAssertionFailedError.Create(AMsg + ': a picture missing');
  if A.PictureFormat <> B.PictureFormat then
    raise EAssertionFailedError.Create(AMsg + ': the format');
  if (A.WidthTwips <> B.WidthTwips) or (A.HeightTwips <> B.HeightTwips) then
    raise EAssertionFailedError.Create(AMsg + ': the size');
  if A.RawRtf <> B.RawRtf then raise EAssertionFailedError.Create(AMsg + ': the group');
  if A.RawUc <> B.RawUc then raise EAssertionFailedError.Create(AMsg + ': the \uc');
  if not SameBytes(A.MakeImageData, B.MakeImageData) then
    raise EAssertionFailedError.CreateFmt('%s: the bytes (%d and %d of them)',
      [AMsg, Length(A.MakeImageData), Length(B.MakeImageData)]);
  da := A.DisplayData(fa, sa, ca);
  db := B.DisplayData(fb, sb, cb);
  if (da <> db) or (da and ((fa <> fb) or (sa <> sb) or (ca <> cb))) then
    raise EAssertionFailedError.CreateFmt('%s: what is shown (%s %d %d, %s %d %d)',
      [AMsg, BoolToStr(da, True), sa, ca, BoolToStr(db, True), sb, cb]);
end;

{ ---- tests ---- }

{ A 20 KB and a 2 MB PNG each in a paragraph of its own, read lazily: parsing the paragraph
  makes no byte of it from hex and copies none; what the parse scanned grows by the second
  picture's extra bytes only (its group's end is found). }
procedure TTyRichPictureParseTest.TestAPictureParagraphIsParsedWithoutConvertingItsData;
var
  i, para: Integer;
  data: array[0..1] of TBytes;
  files: array[0..1] of TBytes;
  parsed: array[0..1] of Int64;
  d: TTyRichDocument;
  load: TTyRtfLoad;
  pic: TTyRichPicture;
begin
  data[0] := NoisePng(82, 82, 2463534242);
  data[1] := NoisePng(820, 820, 2463534242);
  AssertTrue(Format('a picture of about 20 KB (%d bytes)', [Length(data[0])]),
    (Length(data[0]) > 15000) and (Length(data[0]) < 30000));
  AssertTrue(Format('a picture of about 2 MB (%d bytes)', [Length(data[1])]),
    (Length(data[1]) > 1900000) and (Length(data[1]) < 2300000));
  for i := 0 to 1 do
  begin
    files[i] := DocWith(PictGroup('|pngblip', HexOf(data[i], 64, False)));
    d := LoadDoc(files[i], False);
    try
      load := TyRichRtfLoadOf(d);
      AssertTrue('a lazy load', (load <> nil) and not load.Whole);
      AssertEquals('nothing parsed by opening', 0, load.ParsedBytes);
      d.BeginRead;
      try
        pic := FirstPicture(d, para);
        AssertTrue('the picture is read', pic <> nil);
        AssertEquals(IntToStr(i) + ': no picture byte made from hex digits', 0,
          load.PictureBytesConverted);
        AssertEquals(IntToStr(i) + ': no picture byte copied', 0, load.PictureBytesCopied);
        parsed[i] := load.ParsedBytes;
        // its bytes when asked for: the file's
        AssertTrue(IntToStr(i) + ': its bytes', SameBytes(data[i], pic.MakeImageData));
      finally
        d.EndRead;
      end;
    finally
      d.Free;
    end;
  end;
  // (the larger file's last paragraphs may be an interval of their own, not parsed for it)
  AssertTrue(Format('what the parse scanned grows by the group''s extra bytes only (%d, %d)',
    [parsed[1] - parsed[0], Length(files[1]) - Length(files[0])]),
    parsed[1] - parsed[0] <= Length(files[1]) - Length(files[0]));
  AssertTrue('the group was scanned to its end', parsed[1] >= 2 * Length(data[1]));
end;

type
  TPictCase = record
    Name: string;
    Group: RawByteString;
    Bytes: TBytes;          // nil: what a converting reader (a fragment) makes of it
    Converts: Boolean;      // the file puts the bytes so that a parse converts them
  end;
  TPictCases = array of TPictCase;

function Cases: TPictCases;
var
  png, jpg, wmf, small: TBytes;
  hx: RawByteString;
  n: Integer;

  procedure Add(const AName: string; const AGroup: RawByteString; const ABytes: TBytes;
    AConverts: Boolean);
  begin
    SetLength(Result, n + 1);
    Result[n].Name := AName;
    Result[n].Group := AGroup;
    Result[n].Bytes := ABytes;
    Result[n].Converts := AConverts;
    Inc(n);
  end;

begin
  Result := nil;
  n := 0;
  png := NoisePng(30, 20, 77);
  jpg := JpegOf(40, 30);
  wmf := SingleBitmapWmf;
  small := NoisePng(3, 2, 5);
  Add('PNG, lines of hex', PictGroup('|pngblip', HexOf(png, 64, False)), png, False);
  Add('JPEG, upper case on one line', PictGroup('|jpegblip', HexOf(jpg, 0, True)), jpg, False);
  Add('a metafile of one bitmap', PictGroup('|wmetafile8', HexOf(wmf, 39, False)), wmf, False);
  Add('a metafile, binary', Bar('{|pict|wmetafile8|picw40|pich30|bin' + IntToStr(Length(wmf)) +
    ' ') + StrOf(wmf) + '}', wmf, False);
  Add('PNG, binary', Bar('{|pict|pngblip|picw40|pich30|picwgoal600|pichgoal450' + #13#10 +
    '|bin' + IntToStr(Length(png)) + ' ') + StrOf(png) + '}', png, False);
  // a lone digit at the end is dropped; spaces and tabs between digits are passed over
  hx := HexOf(small, 5, False);
  Add('PNG, spaces, a lone digit', PictGroup('|pngblip', ' ' + Copy(hx, 1, 7) + ' '#9 +
    Copy(hx, 8, MaxInt) + 'a'), small, False);
  // a word between the digits: they are not one stretch, and the parse converts them
  hx := HexOf(png, 0, False);
  Add('PNG, a word inside its digits', PictGroup('|pngblip', Copy(hx, 1, 100) +
    Bar('|picscalex100 ') + Copy(hx, 101, MaxInt)), png, True);
  Add('PNG, an escape inside its digits', PictGroup('|pngblip', Copy(hx, 1, 64) + Bar('|''41') +
    Copy(hx, 65, MaxInt)), png, True);
  // Word's pair: the first one is the picture, the second is passed over
  Add('Word''s shppict pair', Bar('{|*|shppict') + PictGroup('|pngblip', HexOf(png, 64, False)) +
    Bar('}{|nonshppict') + PictGroup('|wmetafile8', HexOf(wmf, 64, False)) + '}', png, False);
  Add('Word''s shppict pair, binary', Bar('{|*|shppict{|pict|pngblip|picw40|pich30|bin' +
    IntToStr(Length(png)) + ' ') + StrOf(png) + Bar('}}{|nonshppict') +
    PictGroup('|wmetafile8', HexOf(wmf, 64, False)) + '}', png, False);
  // no data, and data in a group of its own inside the picture
  Add('no data', PictGroup('|pngblip', ''), nil, False);
  Add('data in a group inside it', PictGroup('|pngblip', '{' + HexOf(small, 0, False) + '}'),
    nil, False);
end;

{ Each way a file puts a picture's bytes, read lazily, read whole, read as a fragment (a
  reader of the file's bytes like a lazy one) and by a parser that converts them as it reads:
  the same picture - format, size, group, \uc, bytes,
  what is shown -, the bytes those the file was made of; the lazy and the whole reads convert
  and copy nothing unless the digits are not one stretch; open and save is the file. }
procedure TTyRichPictureParseTest.TestThePicturesBytesAreTheSameReadLazilyWholeOrAsAFragment;
var
  cs: TPictCases;
  c: TPictCase;
  b: TBytes;
  lazy, whole, frag: TTyRichDocument;
  pl, pw, pf, pc: TTyRichPicture;
  k, para: Integer;
  load: TTyRtfLoad;
begin
  cs := Cases;
  for k := 0 to High(cs) do
  begin
    c := cs[k];
    b := DocWith(c.Group);
    lazy := LoadDoc(b, False);
    whole := nil;
    frag := nil;
    try
      whole := LoadDoc(b, True);
      frag := ReadFragment(b);
      lazy.BeginRead;
      whole.BeginRead;
      frag.BeginRead;
      try
        pl := FirstPicture(lazy, para);
        pw := FirstPicture(whole, para);
        pf := FirstPicture(frag, para);
        AssertTrue(c.Name + ': a picture read lazily', pl <> nil);
        AssertEquals(c.Name + ': read lazily, its bytes are the file''s', not c.Converts, pl.InFile);
        AssertEquals(c.Name + ': read whole, too', not c.Converts, pw.InFile);
        CheckSamePicture(c.Name + ': lazy and whole', pl, pw);
        CheckSamePicture(c.Name + ': lazy and a fragment', pl, pf);
        pc := ConvertingRead(b);
        try
          AssertTrue(c.Name + ': a converting reader has its own bytes', not pc.InFile);
          CheckSamePicture(c.Name + ': lazy and a converting reader', pl, pc);
        finally
          pc.Release;
        end;
        if c.Bytes <> nil then
          AssertTrue(c.Name + ': the bytes the file was made of', SameBytes(c.Bytes, pl.MakeImageData));
        load := TyRichRtfLoadOf(lazy);
        if not c.Converts then
        begin
          AssertEquals(c.Name + ': nothing converted', 0, load.PictureBytesConverted);
          AssertEquals(c.Name + ': nothing copied', 0, load.PictureBytesCopied);
          AssertEquals(c.Name + ': nothing converted reading it whole', 0,
            TyRichRtfLoadOf(whole).PictureBytesConverted);
          AssertEquals(c.Name + ': nothing copied reading it whole', 0,
            TyRichRtfLoadOf(whole).PictureBytesCopied);
        end;
      finally
        frag.EndRead;
        whole.EndRead;
        lazy.EndRead;
      end;
      AssertTrue(c.Name + ': open and save lazily is the file', SameBytes(b, SaveOf(lazy)));
      AssertTrue(c.Name + ': open and save whole is the file', SameBytes(b, SaveOf(whole)));
    finally
      frag.Free;
      whole.Free;
      lazy.Free;
    end;
  end;
end;

{ The samples with pictures and the generated documents: every paragraph read (its pictures
  made), then saved - the file, lazily and whole. }
procedure TTyRichPictureParseTest.TestOpenAndSaveWithPicturesIsTheFile;
const
  Samples: array[0..2] of string = ('re-zh-picture.rtf', 'wp-zh-picture.rtf', 'word-unknown.rtf');
var
  files: array of TBytes;
  cs: TPictCases;
  i, k, n: Integer;
  d: TTyRichDocument;
  full: Boolean;
begin
  cs := Cases;
  SetLength(files, Length(Samples) + Length(cs));
  for i := 0 to High(Samples) do files[i] := Fixture(Samples[i]);
  for i := 0 to High(cs) do files[Length(Samples) + i] := DocWith(cs[i].Group);
  for i := 0 to High(files) do
    for full := False to True do
    begin
      d := LoadDoc(files[i], full);
      try
        n := 0;
        d.BeginRead;
        try
          for k := 0 to d.Text.ParaCount - 1 do
            if Length(d.RunsOf(k)) > 0 then Inc(n);
        finally
          d.EndRead;
        end;
        AssertTrue(IntToStr(i) + ': read', n > 0);
        AssertTrue(Format('%d (whole %s): open and save is the file', [i, BoolToStr(full, True)]),
          SameBytes(files[i], SaveOf(d)));
      finally
        d.Free;
      end;
    end;
end;

{ A character typed before a picture, Chinese and Latin: the paragraph is written from the
  model, the picture's group as the file has it; read back, the same picture and the text. }
procedure TTyRichPictureParseTest.TestAnEditBesideAPictureWritesItsGroupAsTheFileHasIt;
var
  cs: TPictCases;
  b, saved: TBytes;
  d, back: TTyRichDocument;
  pic, got: TTyRichPicture;
  k, para, para2: Integer;
  at: TTyRichPos;
  zh: UTF8String;
  t: UTF8String;
begin
  cs := Cases;
  // U+4E2D as UTF-8
  zh := #$E4#$B8#$AD;
  for k := 0 to High(cs) do
  begin
    if cs[k].Bytes = nil then Continue;
    b := DocWith(cs[k].Group);
    d := LoadDoc(b, False);
    back := nil;
    try
      d.BeginRead;
      try
        pic := FirstPicture(d, para);
        at := PicturePos(d, para);
      finally
        d.EndRead;
      end;
      AssertTrue(cs[k].Name + ': a picture', at >= 0);
      AssertTrue(cs[k].Name + ': typed', d.Execute(TTyRichInsertText.Create(at, zh + 'x')));
      saved := SaveOf(d);
      AssertTrue(cs[k].Name + ': the group as the file has it',
        Pos(cs[k].Group, StrOf(saved)) > 0);
      back := ReadFragment(saved);
      back.BeginRead;
      d.BeginRead;
      try
        got := FirstPicture(back, para2);
        pic := FirstPicture(d, para);
        AssertTrue(cs[k].Name + ': read back, the bytes', SameBytes(cs[k].Bytes, got.MakeImageData));
        CheckSamePicture(cs[k].Name + ': read back', pic, got);
        t := back.Text.GetText(back.Text.ParaStart(para2), back.Text.ParaLength(para2));
        AssertTrue(cs[k].Name + ': the Chinese typed is there', Pos(zh + 'x', t) > 0);
      finally
        d.EndRead;
        back.EndRead;
      end;
      d.Undo;
      AssertTrue(cs[k].Name + ': undone, the file', SameBytes(b, SaveOf(d)));
    finally
      back.Free;
      d.Free;
    end;
  end;
end;

{ A picture read lazily, cloned and taken through the filter between two documents (what a
  copy into another document does with it): each owns its bytes - its data counted as its own
  - and, the first document gone, they are the file's bytes still. The picture in its
  document counts only itself: the file's bytes are the load's. }
procedure TTyRichPictureParseTest.TestAPictureThatLeavesItsDocumentOwnsItsBytes;
var
  png: TBytes;
  a, b: TTyRichDocument;
  pic: TTyRichPicture;
  cl, mapped: TTyRichObject;
  flt: TTyRichFragmentFilter;
  para: Integer;
  s: UTF8String;
  n: Int64;
begin
  png := NoisePng(60, 40, 99);
  a := LoadDoc(DocWith(PictGroup('|pngblip', HexOf(png, 64, False))), False);
  b := LoadDoc(DocWith('x'), False);
  cl := nil;
  mapped := nil;
  try
    a.BeginRead;
    try
      pic := FirstPicture(a, para);
      AssertTrue('a picture', pic <> nil);
      AssertEquals('in its document it counts itself only', pic.InstanceSize, pic.DataBytes);
      AssertTrue('nothing of its own to share', pic.SharedData(n) = nil);
      cl := pic.Clone;
      cl.AddRef;
      flt := TyRichFragmentFilterFor(a, b);
      try
        mapped := flt.MapObject(pic, s);
        AssertTrue('the filter keeps a picture', mapped is TTyRichPicture);
        mapped.AddRef;
      finally
        flt.Free;
      end;
    finally
      a.EndRead;
    end;
    AssertTrue('the clone owns its bytes', cl.DataBytes >= cl.InstanceSize + Length(png));
    AssertFalse('the clone is in no file', TTyRichPicture(cl).InFile);
    AssertFalse('nor what went to the other document', TTyRichPicture(mapped).InFile);
    AssertTrue('the clone shares them as its own', cl.SharedData(n) <> nil);
    AssertTrue('what went to the other document owns its bytes',
      mapped.DataBytes >= mapped.InstanceSize + Length(png));
    FreeAndNil(a);
    AssertTrue('the clone''s bytes outlive the document', SameBytes(png, TTyRichPicture(cl).MakeImageData));
    AssertTrue('the other''s too', SameBytes(png, TTyRichPicture(mapped).MakeImageData));
    AssertEquals('the group the clone keeps', PictGroup('|pngblip', HexOf(png, 64, False)),
      TTyRichPicture(cl).RawRtf);
  finally
    if mapped <> nil then mapped.Release;
    if cl <> nil then cl.Release;
    b.Free;
    a.Free;
  end;
end;

{ A picture read lazily, resized: saved at its new size with the file's bytes; undone, the
  file. Text replaced in its paragraph: its group as the file has it; undone, the file. }
procedure TTyRichPictureParseTest.TestResizeReplaceAndUndoKeepTheFilesBytes;
var
  png, b, saved: TBytes;
  d, back: TTyRichDocument;
  pic, got: TTyRichPicture;
  para: Integer;
  at: TTyRichPos;
  group: RawByteString;
begin
  png := NoisePng(50, 30, 1234);
  group := PictGroup('|pngblip', HexOf(png, 64, False));
  b := DocWith(group);
  d := LoadDoc(b, False);
  back := nil;
  try
    d.BeginRead;
    try
      pic := FirstPicture(d, para);
      at := PicturePos(d, para);
    finally
      d.EndRead;
    end;
    AssertTrue('resized', d.Execute(TTyRichResizeObject.Create(at, 1200, 900)));
    saved := SaveOf(d);
    back := ReadFragment(saved);
    back.BeginRead;
    try
      got := FirstPicture(back, para);
      AssertTrue('read back: a picture', got <> nil);
      AssertTrue('read back: the bytes', SameBytes(png, got.MakeImageData));
      AssertEquals('read back: the width', 1200, got.WidthTwips);
      AssertEquals('read back: the height', 900, got.HeightTwips);
    finally
      back.EndRead;
    end;
    FreeAndNil(back);
    d.BeginRead;
    try
      got := TTyRichPicture(d.ObjectAt(at));
      AssertTrue('resized: the same bytes', SameBytes(png, got.MakeImageData));
      AssertTrue('resized: where they are in the file, shared', got.InFile and
        (got.DataIdentity = pic.DataIdentity));
    finally
      d.EndRead;
    end;
    d.Undo;
    AssertTrue('the resize undone: the file', SameBytes(b, SaveOf(d)));
    AssertTrue('replaced', d.Execute(TTyRichReplaceAllCommand.Create(d, 'after', 'past', [], 0, -1)));
    saved := SaveOf(d);
    AssertTrue('replaced: the group as the file has it', Pos(group, StrOf(saved)) > 0);
    AssertTrue('replaced: the new text', Pos('past the picture', StrOf(saved)) > 0);
    d.Undo;
    AssertTrue('the replace undone: the file', SameBytes(b, SaveOf(d)));
  finally
    back.Free;
    d.Free;
  end;
end;

{ Every file with pictures, read lazily (paragraphs in an order of their own) and whole: the
  same objects in every paragraph - for a picture its format, size, group, \uc and bytes. }
procedure TTyRichPictureParseTest.TestLazyAndWholeAgreeOnEveryFileWithPictures;
const
  Samples: array[0..2] of string = ('re-zh-picture.rtf', 'wp-zh-picture.rtf', 'word-unknown.rtf');
var
  files: array of TBytes;
  cs: TPictCases;
  i, k, j, m, pics: Integer;
  lazy, whole: TTyRichDocument;
  rl, rw: TTyRunArray;
begin
  cs := Cases;
  SetLength(files, Length(Samples) + Length(cs));
  for i := 0 to High(Samples) do files[i] := Fixture(Samples[i]);
  for i := 0 to High(cs) do files[Length(Samples) + i] := DocWith(cs[i].Group);
  pics := 0;
  for i := 0 to High(files) do
  begin
    lazy := LoadDoc(files[i], False);
    whole := nil;
    try
      whole := LoadDoc(files[i], True);
      AssertEquals(IntToStr(i) + ': paragraphs', whole.Text.ParaCount, lazy.Text.ParaCount);
      lazy.BeginRead;
      whole.BeginRead;
      try
        for m := 0 to lazy.Text.ParaCount - 1 do
        begin
          // from the end backwards: other intervals parsed first
          k := lazy.Text.ParaCount - 1 - m;
          rl := lazy.RunsOf(k);
          rw := whole.RunsOf(k);
          AssertEquals(Format('%d, paragraph %d: runs', [i, k]), Length(rw), Length(rl));
          for j := 0 to High(rl) do
            if (rl[j].Obj is TTyRichPicture) or (rw[j].Obj is TTyRichPicture) then
            begin
              CheckSamePicture(Format('%d, paragraph %d', [i, k]), TTyRichPicture(rl[j].Obj),
                TTyRichPicture(rw[j].Obj));
              Inc(pics);
            end;
        end;
      finally
        whole.EndRead;
        lazy.EndRead;
      end;
    finally
      whole.Free;
      lazy.Free;
    end;
  end;
  AssertTrue(Format('pictures compared: %d', [pics]), pics >= Length(cs));
end;

{ A control shows a PNG and a metafile of one bitmap, both hex digits of its file: the paint
  makes none of their bytes, the idle steps that decode them make each picture's bytes once -
  the metafile's too, walked for its bitmap and decoded from the same bytes - and look at no
  digit only to count it. }
procedure TTyRichPictureParseTest.TestADecodeMakesAPicturesBytesOnce;
var
  png, wmf: TBytes;
  rtf: RawByteString;
  ctl: TTyStyleController;
  rich: TPictRich;
  bmp: TBitmap;
  st: TBytesStream;
  made, counted, decodes: Int64;
begin
  png := NoisePng(40, 30, 31337);
  wmf := SingleBitmapWmf;
  rtf := Bar(CHead + 'one ') + PictGroup('|pngblip', HexOf(png, 64, False)) + Bar(' two ') +
    PictGroup('|wmetafile8', HexOf(wmf, 64, False)) + Bar(' three|par') + #13#10 + '}';
  ctl := TTyStyleController.Create(nil);
  rich := TPictRich.Create(nil);
  bmp := TBitmap.Create;
  st := TBytesStream.Create(BytesOf(rtf));
  try
    rich.Controller := ctl;
    rich.Font.PixelsPerInch := 96;
    rich.SetBounds(0, 0, 600, 400);
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(600, 400);
    rich.LoadFromStream(st);
    rich.FinishLoading;
    made := TyRichPictureBytesMade;
    counted := TyRichPictureDigitsCounted;
    decodes := rich.Layouter.PictureDecodes;
    rich.PaintInto(bmp);
    AssertEquals('the paint makes no picture''s bytes', made, TyRichPictureBytesMade);
    while rich.Step do ;
    rich.PaintInto(bmp);
    AssertEquals('both decoded', decodes + 2, rich.Layouter.PictureDecodes);
    AssertEquals('each picture''s bytes made once', Int64(Length(png) + Length(wmf)),
      TyRichPictureBytesMade - made);
    AssertEquals('no digit looked at only to count it', counted, TyRichPictureDigitsCounted);
  finally
    st.Free;
    bmp.Free;
    rich.Free;
    ctl.Free;
  end;
end;

{ A \bin PNG read lazily, resized: saved at the new size, written from the model with the
  file's bytes as hex, made once for the save; read back, the same bytes. }
procedure TTyRichPictureParseTest.TestABinaryPictureResizedIsSavedWithItsBytes;
var
  png, b, saved: TBytes;
  d, back: TTyRichDocument;
  pic, got: TTyRichPicture;
  para: Integer;
  at: TTyRichPos;
  made: Int64;
begin
  png := NoisePng(30, 20, 4321);
  b := DocWith(Bar('{|pict|pngblip|picw30|pich20|picwgoal450|pichgoal300|bin' +
    IntToStr(Length(png)) + ' ') + StrOf(png) + '}');
  d := LoadDoc(b, False);
  back := nil;
  try
    d.BeginRead;
    try
      pic := FirstPicture(d, para);
      at := PicturePos(d, para);
      AssertTrue('in the file', pic.InFile);
    finally
      d.EndRead;
    end;
    AssertTrue('resized', d.Execute(TTyRichResizeObject.Create(at, 900, 600)));
    made := TyRichPictureBytesMade;
    saved := SaveOf(d);
    AssertEquals('the save makes its bytes once', Int64(Length(png)), TyRichPictureBytesMade - made);
    back := ReadFragment(saved);
    back.BeginRead;
    try
      got := FirstPicture(back, para);
      AssertTrue('read back: a picture', got <> nil);
      AssertEquals('read back: the width', 900, got.WidthTwips);
      AssertTrue('read back: the bytes', SameBytes(png, got.MakeImageData));
    finally
      back.EndRead;
    end;
    d.Undo;
    AssertTrue('undone: the file', SameBytes(b, SaveOf(d)));
  finally
    back.Free;
    d.Free;
  end;
end;

{ What a paint asks of a picture of its file's bytes before any decode: one hex digit is no
  byte (nothing to show), nor is a metafile kind nothing here draws (EMF); two digits of a
  PNG, and a metafile of hex digits, may show. }
procedure TTyRichPictureParseTest.TestWhatMayShowWithoutReadingTheBytes;

  function MayShowOf(const AGroup: RawByteString): Boolean;
  var
    d: TTyRichDocument;
    pic: TTyRichPicture;
    para: Integer;
  begin
    d := LoadDoc(DocWith(AGroup), False);
    try
      d.BeginRead;
      try
        pic := FirstPicture(d, para);
        AssertTrue('in the file', pic.InFile);
        Result := pic.MayShow;
      finally
        d.EndRead;
      end;
    finally
      d.Free;
    end;
  end;

begin
  AssertFalse('one digit', MayShowOf(PictGroup('|pngblip', ' 8 ')));
  AssertTrue('two digits', MayShowOf(PictGroup('|pngblip', ' 8 9 ')));
  AssertFalse('an EMF', MayShowOf(PictGroup('|emfblip', HexOf(SingleBitmapWmf, 64, False))));
  AssertTrue('a metafile', MayShowOf(PictGroup('|wmetafile8', HexOf(SingleBitmapWmf, 64, False))));
  AssertFalse('an unknown format', MayShowOf(PictGroup('', '89504e47')));
end;

{ A picture whose group as read ends in a control word (a file cut off inside it): the text
  written after it is set apart by an empty group, so the word stays the word it was; one
  whose group ends in its brace is followed by the text at once. }
procedure TTyRichPictureParseTest.TestAGroupThatEndsInAWordIsEndedBeforeTheTextAfterIt;

  function Saved(const ARaw: RawByteString): RawByteString;
  var
    d: TTyRichDocument;
  begin
    d := TTyRichDocument.Create;
    try
      AssertTrue('text', d.Execute(TTyRichInsertText.Create(0, 'ab')));
      AssertTrue('a picture', d.Execute(TTyRichInsertObject.Create(1,
        TTyRichPicture.Create(rpfPng, NoisePng(2, 2, 7), 300, 300, ARaw))));
      Result := StrOf(SaveOf(d));
    finally
      d.Free;
    end;
  end;

begin
  AssertTrue('a word at its end: ended', Pos(Bar('{|pict|pngblip 89|picscalex100{}b'),
    Saved(Bar('{|pict|pngblip 89|picscalex100'))) > 0);
  AssertTrue('a brace at its end: the text at once', Pos(Bar('{|pict|pngblip 89}b'),
    Saved(Bar('{|pict|pngblip 89}'))) > 0);
end;

initialization
  RegisterTest(TTyRichPictureParseTest);

end.
