unit test.richedit.wmf;

{ A Windows metafile whose whole drawing is one bitmap is shown as that bitmap: WordPad saves
  every picture as such a metafile (a \pict group with \wmetafile8), and Word writes a
  formula's fallback picture that way. TyWmfSingleBitmap walks the records and finds the bitmap without
  reading past the bytes it is given; TTyRichPicture.DisplayData hands a decoder that bitmap
  (or the data of a PNG, JPEG, BMP or DIB) and nothing for any other metafile. }

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.RtfRead,
  tyControls.RichEdit.Wmf;

type
  TTyRichWmfTest = class(TTestCase)
  published
    procedure TestWordPadPicturesShowAsTheirBitmap;
    procedure TestWordFormulaFallbackIsOneBitmap;
    procedure TestAnythingElseDrawnMakesItAPlaceholder;
    procedure TestThePlaceableHeaderIsAccepted;
    procedure TestTruncatedAndLyingRecordsAreRejected;
    procedure TestWhatEachFormatDisplays;
  end;

implementation

const
  SrcCopy = $00CC0020;

function FixtureDir: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'tests' + PathDelim + 'fixtures' +
    PathDelim + 'rtf' + PathDelim;
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

function LoadBytes(const ABytes: TBytes): TTyRichDocument;
var
  s: TBytesStream;
begin
  Result := TTyRichDocument.Create;
  s := TBytesStream.Create(ABytes);
  try
    try
      TyRichLoadRtf(Result, s);
    except
      Result.Free;
      raise;
    end;
  finally
    s.Free;
  end;
end;

{ Every picture of the document, in order. }
function PicturesOf(ADoc: TTyRichDocument): TFPList;
var
  p, i: Integer;
  r: TTyRunArray;
begin
  Result := TFPList.Create;
  for p := 0 to ADoc.Text.ParaCount - 1 do
  begin
    r := ADoc.RunsOf(p);
    for i := 0 to High(r) do
      if r[i].Obj is TTyRichPicture then Result.Add(r[i].Obj);
  end;
end;

function U16(const B: TBytes; AAt: Integer): Integer;
begin
  Result := B[AAt] or (B[AAt + 1] shl 8);
end;

function U32(const B: TBytes; AAt: Integer): LongInt;
begin
  Result := LongInt(Cardinal(U16(B, AAt)) or (Cardinal(U16(B, AAt + 2)) shl 16));
end;

{ ---- building metafiles ---- }

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

procedure PutBytes(var B: TBytes; const AMore: TBytes);
var
  n: Integer;
begin
  n := Length(B);
  SetLength(B, n + Length(AMore));
  if Length(AMore) > 0 then Move(AMore[0], B[n], Length(AMore));
end;

{ A 2 x 2 bitmap of 24 bits: BITMAPINFOHEADER and two rows of 8 bytes. }
function SmallDib: TBytes;
var
  i: Integer;
begin
  Result := nil;
  Put32(Result, 40);
  Put32(Result, 2);
  Put32(Result, 2);
  Put16(Result, 1);
  Put16(Result, 24);
  for i := 1 to 6 do Put32(Result, 0);
  for i := 1 to 8 do Put16(Result, $7F7F);
end;

function MetaHeader: TBytes;
begin
  Result := nil;
  Put16(Result, 1);       // in memory
  Put16(Result, 9);       // header words
  Put16(Result, $0300);
  Put32(Result, 0);       // total size: not checked
  Put16(Result, 0);
  Put32(Result, 0);
  Put16(Result, 0);
end;

procedure PutRecord(var B: TBytes; AFunction: Integer; const AParams: TBytes);
begin
  Put32(B, Cardinal(3 + Length(AParams) div 2));
  Put16(B, AFunction);
  PutBytes(B, AParams);
end;

{ META_STRETCHDIB's parameters and the 2 x 2 bitmap; the source rectangle is the whole
  bitmap unless the caller names another. }
function StretchDib(ARop: Cardinal = SrcCopy; ASrcHeight: Integer = 2; ASrcWidth: Integer = 2;
  ASrcY: Integer = 0; ASrcX: Integer = 0): TBytes;
var
  i: Integer;
begin
  Result := nil;
  Put32(Result, ARop);
  Put16(Result, 0);       // DIB_RGB_COLORS
  Put16(Result, ASrcHeight);
  Put16(Result, ASrcWidth);
  Put16(Result, ASrcY);
  Put16(Result, ASrcX);
  for i := 1 to 4 do Put16(Result, 2);   // the destination: height, width, y, x
  PutBytes(Result, SmallDib);
end;

{ A metafile whose one record is the bitmap record AFunction with AParams. }
function WmfOf(AFunction: Integer; const AParams: TBytes): TBytes;
begin
  Result := MetaHeader;
  PutRecord(Result, AFunction, AParams);
  PutRecord(Result, 0, nil);
end;

{ A 32-bit DIB header that announces AWidth x AHeight, followed by 16 bytes of bits. }
function LyingDib(AWidth, AHeight: Cardinal): TBytes;
var
  i: Integer;
begin
  Result := nil;
  Put32(Result, 40);
  Put32(Result, AWidth);
  Put32(Result, AHeight);
  Put16(Result, 1);
  Put16(Result, 32);
  for i := 1 to 6 do Put32(Result, 0);
  for i := 1 to 8 do Put16(Result, $7F7F);
end;

function TwoWords(A, B: Integer): TBytes;
begin
  Result := nil;
  Put16(Result, A);
  Put16(Result, B);
end;

const
  FnWindowExt = $020C;
  FnMoveTo = $0214;
  FnLineTo = $0213;
  FnStretchDib = $0F43;
  FnEof = 0;

{ A metafile: header, window extent, AMiddle records, the bitmap, AAfter records, end. }
function Wmf(const AMiddle: array of Integer; const AAfter: array of Integer;
  ARop: Cardinal = SrcCopy): TBytes;
var
  i: Integer;
begin
  Result := MetaHeader;
  PutRecord(Result, FnWindowExt, TwoWords(2, 2));
  for i := 0 to High(AMiddle) do PutRecord(Result, AMiddle[i], TwoWords(1, 1));
  PutRecord(Result, FnStretchDib, StretchDib(ARop));
  for i := 0 to High(AAfter) do
    if AAfter[i] = FnStretchDib then PutRecord(Result, FnStretchDib, StretchDib)
    else PutRecord(Result, AAfter[i], TwoWords(1, 1));
  PutRecord(Result, FnEof, nil);
end;

procedure CheckDibHeader(const AMsg: string; const AData: TBytes; AStart, ACount, AWidth,
  AHeight, ABits: Integer);
begin
  TAssert.AssertTrue(AMsg + ': the range is inside the data', (AStart >= 0) and (ACount > 40) and
    (AStart + ACount <= Length(AData)));
  TAssert.AssertEquals(AMsg + ': biSize', 40, U32(AData, AStart));
  TAssert.AssertEquals(AMsg + ': width', AWidth, U32(AData, AStart + 4));
  TAssert.AssertEquals(AMsg + ': height', AHeight, U32(AData, AStart + 8));
  TAssert.AssertEquals(AMsg + ': bit count', ABits, U16(AData, AStart + 14));
end;

{ META_STRETCHDIB of a 2 x 2 bitmap of 8 bits, RLE-compressed, two colours, six bytes of
  bits; its header announces ASizeImage bytes. }
function RleRecord(ASizeImage: Cardinal): TBytes;
var
  i: Integer;
begin
  Result := nil;
  Put32(Result, SrcCopy);
  Put16(Result, 0);
  Put16(Result, 2);
  Put16(Result, 2);
  Put16(Result, 0);
  Put16(Result, 0);
  for i := 1 to 4 do Put16(Result, 2);
  Put32(Result, 40);
  Put32(Result, 2);
  Put32(Result, 2);
  Put16(Result, 1);
  Put16(Result, 8);
  Put32(Result, 1);            // BI_RLE8
  Put32(Result, ASizeImage);
  Put32(Result, 0);
  Put32(Result, 0);
  Put32(Result, 2);            // two colours
  Put32(Result, 0);
  Put32(Result, 0);
  Put32(Result, $00FFFFFF);
  // two pixels of colour 1, end of line; the same; end of bitmap
  Put16(Result, $0102);
  Put16(Result, $0000);
  Put16(Result, $0100);
end;

{ ---- tests ---- }

procedure TTyRichWmfTest.TestWordPadPicturesShowAsTheirBitmap;
const
  // the pasted bitmap is a 24-bit META_STRETCHDIB; the inserted PNG became a 4-bit
  // META_DIBSTRETCHBLT
  Bits: array[0..1] of Integer = (24, 4);
var
  d: TTyRichDocument;
  l: TFPList;
  p: TTyRichPicture;
  i, start, count: Integer;
  fmt: TTyRichPictureFormat;
  bm: TTyWmfBitmap;
begin
  d := LoadBytes(ReadFileBytes(FixtureDir + 'wp-zh-picture.rtf'));
  l := PicturesOf(d);
  try
    AssertEquals('two pictures', 2, l.Count);
    for i := 0 to 1 do
    begin
      p := TTyRichPicture(l[i]);
      AssertTrue(Format('picture %d stays a metafile', [i]), p.PictureFormat = rpfWmf);
      AssertEquals(Format('picture %d: its data is the metafile', [i]), $0001, U16(p.Data, 0));
      AssertTrue(Format('picture %d: written back as read', [i]),
        Pos('{\pict{\*\picprop}\wmetafile8', p.RawRtf) = 1);
      AssertTrue(Format('picture %d shows', [i]), p.DisplayData(fmt, start, count));
      AssertTrue(Format('picture %d shows a DIB', [i]), fmt = rpfDib);
      CheckDibHeader(Format('picture %d', [i]), p.Data, start, count, 96, 64, Bits[i]);
      AssertTrue(Format('picture %d: one bitmap', [i]), TyWmfSingleBitmap(p.Data, bm));
      AssertEquals(Format('picture %d: pixel width', [i]), 96, bm.Width);
      AssertEquals(Format('picture %d: pixel height', [i]), 64, bm.Height);
      AssertEquals(Format('picture %d: the same range', [i]), start, bm.DibStart);
      AssertEquals(Format('picture %d: display width', [i]), 1440, p.WidthTwips);
      AssertEquals(Format('picture %d: display height', [i]), 960, p.HeightTwips);
    end;
  finally
    l.Free;
    d.Free;
  end;
end;

procedure TTyRichWmfTest.TestWordFormulaFallbackIsOneBitmap;
var
  b: TBytes;
  s, pict: RawByteString;
  d, f: TTyRichDocument;
  r: TTyRunArray;
  i, at, depth, k, start, count: Integer;
  o: TTyRichOpaque;
  l: TFPList;
  p: TTyRichPicture;
  fmt: TTyRichPictureFormat;
begin
  b := ReadFileBytes(FixtureDir + 'word-unknown.rtf');
  d := LoadBytes(b);
  try
    // the formula, its picture fallback included, is one object in paragraph 5
    o := nil;
    r := d.RunsOf(5);
    for i := 0 to High(r) do
      if (r[i].Obj is TTyRichOpaque) and
         (Pos('{\mmath{', TTyRichOpaque(r[i].Obj).Bytes) = 1) then
        o := TTyRichOpaque(r[i].Obj);
    AssertNotNull('the formula', o);
    s := o.Bytes;
    AssertTrue('its fallback', Pos('{\mmathPict{\*\shppict', s) > 0);
    AssertTrue('a PNG first', Pos('\pngblip', s) > 0);
  finally
    d.Free;
  end;
  // the \pict group inside \nonshppict, read on its own
  at := Pos('{\nonshppict', s);
  AssertTrue('the metafile''s group', at > 0);
  at := at + Length('{\nonshppict');
  while (at <= Length(s)) and (s[at] <> '{') do Inc(at);
  depth := 0;
  k := at;
  repeat
    if s[k] = '\' then Inc(k)
    else if s[k] = '{' then Inc(depth)
    else if s[k] = '}' then Dec(depth);
    Inc(k);
  until (depth = 0) or (k > Length(s));
  pict := Copy(s, at, k - at);
  AssertTrue('a \pict group', Pos('{\pict', pict) = 1);
  f := LoadBytes(BytesOf('{\rtf1 ' + pict + '}'));
  l := PicturesOf(f);
  try
    AssertEquals('one picture', 1, l.Count);
    p := TTyRichPicture(l[0]);
    AssertTrue('a metafile', p.PictureFormat = rpfWmf);
    // Word's fallback draws nothing but one 8-bit META_DIBSTRETCHBLT of 56 x 24 pixels
    AssertTrue('one bitmap', p.DisplayData(fmt, start, count));
    AssertTrue('shown as a DIB', fmt = rpfDib);
    CheckDibHeader('the formula', p.Data, start, count, 56, 24, 8);
  finally
    l.Free;
    f.Free;
  end;
end;

procedure TTyRichWmfTest.TestAnythingElseDrawnMakesItAPlaceholder;
var
  bm: TTyWmfBitmap;
  b: TBytes;
begin
  b := Wmf([], []);
  AssertTrue('the bitmap alone', TyWmfSingleBitmap(b, bm));
  AssertEquals('width', 2, bm.Width);
  AssertEquals('height', 2, bm.Height);
  // header 18, window extent 10, the record's head 6 and parameters 22
  AssertEquals('where the DIB starts', 18 + 10 + 6 + 22, bm.DibStart);
  AssertEquals('its length', 56, bm.DibCount);
  AssertTrue('a position only', TyWmfSingleBitmap(Wmf([FnMoveTo], []), bm));
  AssertFalse('a line drawn after it', TyWmfSingleBitmap(Wmf([], [FnLineTo]), bm));
  AssertEquals('nothing found', 0, bm.DibCount);
  AssertFalse('a line drawn before it', TyWmfSingleBitmap(Wmf([FnMoveTo, FnLineTo], []), bm));
  AssertFalse('a second bitmap', TyWmfSingleBitmap(Wmf([], [FnStretchDib]), bm));
  AssertFalse('a rectangle', TyWmfSingleBitmap(Wmf([], [$041B]), bm));
  AssertFalse('a clip rectangle', TyWmfSingleBitmap(Wmf([$0416], []), bm));
  AssertFalse('an unknown record', TyWmfSingleBitmap(Wmf([$0999], []), bm));
  AssertFalse('combined with what is below (SRCAND)',
    TyWmfSingleBitmap(Wmf([], [], $008800C6), bm));
  // a part of the bitmap drawn is not the bitmap: the source rectangle must be all of it
  AssertTrue('the whole source', TyWmfSingleBitmap(WmfOf(FnStretchDib, StretchDib), bm));
  AssertFalse('the left column only',
    TyWmfSingleBitmap(WmfOf(FnStretchDib, StretchDib(SrcCopy, 2, 1)), bm));
  AssertFalse('the top row only',
    TyWmfSingleBitmap(WmfOf(FnStretchDib, StretchDib(SrcCopy, 1, 2)), bm));
  AssertFalse('from the second column on',
    TyWmfSingleBitmap(WmfOf(FnStretchDib, StretchDib(SrcCopy, 2, 2, 0, 1)), bm));
  AssertFalse('from the second row on',
    TyWmfSingleBitmap(WmfOf(FnStretchDib, StretchDib(SrcCopy, 2, 2, 1, 0)), bm));
  // no bitmap at all
  b := MetaHeader;
  PutRecord(b, FnWindowExt, TwoWords(2, 2));
  PutRecord(b, FnEof, nil);
  AssertFalse('no bitmap', TyWmfSingleBitmap(b, bm));
end;

procedure TTyRichWmfTest.TestThePlaceableHeaderIsAccepted;
var
  b, plain: TBytes;
  bm: TTyWmfBitmap;
  i: Integer;
begin
  plain := Wmf([], []);
  b := nil;
  Put32(b, $9AC6CDD7);
  for i := 1 to 9 do Put16(b, 0);
  AssertEquals('22 bytes', 22, Length(b));
  PutBytes(b, plain);
  AssertTrue('with the placeable header', TyWmfSingleBitmap(b, bm));
  AssertEquals('the DIB 22 bytes further', 18 + 10 + 6 + 22 + 22, bm.DibStart);
  AssertEquals('width', 2, bm.Width);
  // a damaged metafile header
  plain[2] := 8;
  AssertFalse('a header of 8 words', TyWmfSingleBitmap(plain, bm));
end;

procedure TTyRichWmfTest.TestTruncatedAndLyingRecordsAreRejected;
var
  d: TTyRichDocument;
  l: TFPList;
  data, b: TBytes;
  bm: TTyWmfBitmap;
  n, at, dib: Integer;
begin
  d := LoadBytes(ReadFileBytes(FixtureDir + 'wp-zh-picture.rtf'));
  l := PicturesOf(d);
  try
    data := Copy(TTyRichPicture(l[0]).Data);
  finally
    l.Free;
    d.Free;
  end;
  AssertTrue('the whole metafile', TyWmfSingleBitmap(data, bm));
  dib := bm.DibStart;
  // cut at every byte: never a bitmap, never a read past the end (heaptrc/range checks would
  // show one; the copy has exactly n bytes)
  for n := 0 to Length(data) - 1 do
  begin
    b := Copy(data, 0, n);
    if n = 0 then
      AssertFalse('nothing', TyWmfSingleBitmap(nil, 0, bm))
    else
      AssertFalse(Format('cut at %d', [n]), TyWmfSingleBitmap(b, bm));
  end;
  // the records: header 18, window org 10, window ext 10, then the bitmap at 38
  at := 38;
  AssertEquals('the bitmap record', $0F43, U16(data, at + 4));
  // a size that claims one word more than there is
  b := Copy(data);
  n := (Length(b) - at) div 2 + 1;
  b[at] := Byte(n);
  b[at + 1] := Byte(n shr 8);
  b[at + 2] := Byte(n shr 16);
  b[at + 3] := Byte(n shr 24);
  AssertFalse('a record past the end', TyWmfSingleBitmap(b, bm));
  // a size below the record's own head
  b := Copy(data);
  b[at] := 2;
  b[at + 1] := 0;
  b[at + 2] := 0;
  b[at + 3] := 0;
  AssertFalse('a record of 2 words', TyWmfSingleBitmap(b, bm));
  // a bitmap that claims more rows than its bits hold
  b := Copy(data);
  b[dib + 8] := 65;
  AssertFalse('65 rows in the bits of 64', TyWmfSingleBitmap(b, bm));
  // a header size no bitmap has
  b := Copy(data);
  b[dib + 3] := $7F;
  AssertFalse('biSize unknown', TyWmfSingleBitmap(b, bm));
  // a colour table that claims more than the record holds (24 bits: biClrUsed is allowed)
  b := Copy(data);
  b[dib + 34] := $FF;
  AssertFalse('a colour table past the end', TyWmfSingleBitmap(b, bm));
  // a header whose width times height is past any number: 16 bytes of bits are not
  // 2147483647 x 1073741825 pixels (the product must not wrap into "fits")
  b := nil;
  Put32(b, SrcCopy);
  Put16(b, 0);
  for n := 1 to 8 do Put16(b, 0);
  PutBytes(b, LyingDib($7FFFFFFF, $40000001));
  AssertFalse('a bitmap of 2^61 pixels in 16 bytes', TyWmfSingleBitmap(WmfOf($0F43, b), bm));
  AssertEquals('nothing reported', 0, bm.Width);
  b := nil;
  Put32(b, SrcCopy);
  Put16(b, 0);
  for n := 1 to 8 do Put16(b, 0);
  PutBytes(b, LyingDib(2, $7FFFFFFF));
  AssertFalse('two billion rows of 8 bytes', TyWmfSingleBitmap(WmfOf($0F43, b), bm));
  // the same header with what it announces: 2 x 2, 16 bytes
  b := nil;
  Put32(b, SrcCopy);
  Put16(b, 0);
  Put16(b, 2);
  Put16(b, 2);
  Put16(b, 0);
  Put16(b, 0);
  for n := 1 to 4 do Put16(b, 2);
  PutBytes(b, LyingDib(2, 2));
  AssertTrue('2 x 2 in 16 bytes', TyWmfSingleBitmap(WmfOf($0F43, b), bm));
  // one row more than the bits hold, the source rectangle agreeing with the header
  b := nil;
  Put32(b, SrcCopy);
  Put16(b, 0);
  Put16(b, 3);
  Put16(b, 2);
  Put16(b, 0);
  Put16(b, 0);
  for n := 1 to 4 do Put16(b, 2);
  PutBytes(b, LyingDib(2, 3));
  AssertFalse('2 x 3 in 16 bytes', TyWmfSingleBitmap(WmfOf($0F43, b), bm));
  // a compressed bitmap says how long its bits are: longer than the record is a lie
  AssertTrue('RLE8: 6 bytes of bits', TyWmfSingleBitmap(WmfOf($0F43, RleRecord(6)), bm));
  AssertEquals('RLE8: width', 2, bm.Width);
  AssertFalse('RLE8: 7 bytes announced, 6 there', TyWmfSingleBitmap(WmfOf($0F43, RleRecord(7)), bm));
  AssertFalse('RLE8: no length', TyWmfSingleBitmap(WmfOf($0F43, RleRecord(0)), bm));
end;

procedure TTyRichWmfTest.TestWhatEachFormatDisplays;
var
  p: TTyRichPicture;
  fmt: TTyRichPictureFormat;
  start, count: Integer;
  data: TBytes;
begin
  data := BytesOf('xPNG'#13#10#26#10'rest');
  data[0] := $89;
  p := TTyRichPicture.Create(rpfPng, data, 100, 100);
  try
    AssertTrue('PNG', p.DisplayData(fmt, start, count));
    AssertTrue('as PNG', fmt = rpfPng);
    AssertEquals('from the start', 0, start);
    AssertEquals('all of it', Length(data), count);
  finally
    p.Free;
  end;
  p := TTyRichPicture.Create(rpfEmf, data, 100, 100);
  try
    AssertFalse('EMF: a placeholder', p.DisplayData(fmt, start, count));
  finally
    p.Free;
  end;
  p := TTyRichPicture.Create(rpfWmf, Wmf([], [FnLineTo]), 100, 100);
  try
    AssertFalse('a metafile that draws: a placeholder', p.DisplayData(fmt, start, count));
    AssertTrue('it stays a metafile', p.PictureFormat = rpfWmf);
  finally
    p.Free;
  end;
  p := TTyRichPicture.Create(rpfJpeg, nil, 100, 100);
  try
    AssertFalse('no data', p.DisplayData(fmt, start, count));
  finally
    p.Free;
  end;
  p := TTyRichPicture.Create(rpfWmf, Wmf([], []), 100, 100);
  try
    AssertTrue('one bitmap', p.DisplayData(fmt, start, count));
    AssertTrue('as DIB', fmt = rpfDib);
    AssertEquals('the DIB', 18 + 10 + 6 + 22, start);
    AssertEquals('its length', 56, count);
    AssertEquals('the data stays the metafile', 18 + 10 + 84 + 6, Length(p.Data));
  finally
    p.Free;
  end;
end;

initialization
  RegisterTest(TTyRichWmfTest);
end.
