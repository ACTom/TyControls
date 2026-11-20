unit test.richedit.keptpictures;

{ The picture a block of RTF kept as its bytes carries for readers that cannot draw it - Word's
  equation (\mmathPict), an embedded object (\result), a shape (\shprslt, else its pib
  property) - shown in place of the block: which picture, at what size, in line where the
  block stands, drawn and cached as a picture is; looked for once per object, never at load.
  The block itself stays what it was: one object, its bytes written back as they came,
  selected with a frame and no handles, deleted, copied and pasted whole.

  Layout checks run on the layout tests' device; control checks on the objects suite's
  probe (no window, no system clipboard). Every render check draws on a ground no painting
  produces. The unit is ASCII. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, fpcunit, testregistry, LCLType, Graphics,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Controller,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.Commands,
  tyControls.RichEdit.RtfRead, tyControls.RichEdit.RtfWrite, tyControls.RichEdit.Layout,
  tyControls.RichEdit, test.richedit.layoutdevice, test.richedit.objects;

type
  TTyRichKeptPictureTest = class(TTestCase)
  private
    FDevice: TTyRichTestDevice;
    FLayouter: TTyRichLayouter;
    FDocs: TFPList;
    FLayouts: TFPList;
    FCtl: TTyStyleController;
    FRich: TObjProbe;
    function Doc(const ARtf: RawByteString; AWhole: Boolean = False): TTyRichDocument;
    function Lay(ADoc: TTyRichDocument; AIndex, AWidth: Integer; APPI: Integer = 96): TTyParaLayout;
    function FragAt(L: TTyParaLayout; APos: Integer): TTyRichFragment;
    { Paragraph 0 of ARtf laid out 1000 pixels wide: the box of its character 2. }
    function BoxOf(const ARtf: RawByteString; out AW, AH: Integer; APPI: Integer = 96): TTyRichObject;
    { Paragraph 0 of ARtf painted on the ground: the colour at the middle of character 2's box. }
    function MiddleColour(const ARtf: RawByteString): TBGRAPixel;
    function NewProbe: TObjProbe;
    procedure LoadRtf(const S: RawByteString);
    function SaveRtf: RawByteString;
    procedure PaintAll;
    procedure Settle;
    function BoxRect(APos: TTyRichPos): TRect;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAWordEquationIsLaidOutAndDrawnAsItsPicture;
    procedure TestEachKindShowsThePictureItCarries;
    procedure TestTheFirstPictureAndTheResultBeforePib;
    procedure TestOfWordsPairTheFirstThatCanBeDrawn;
    procedure TestWhatCannotBeDrawnStaysAsItWas;
    procedure TestTheSizeIsThePicturesOwnDisplaySize;
    procedure TestWiderThanTheTextAsAPictureIs;
    procedure TestLookedForOncePerObjectAndNotAtLoad;
    procedure TestOpenedAndSavedAsItCameAndAnInsertKeepsItsBytes;
    procedure TestReadOnDemandIsReadWhole;
    procedure TestOneCaretStepAClickAFrameNoHandles;
    procedure TestResizeIsRefused;
    procedure TestDeleteUndoCopyAndPaste;
    procedure TestInAShownFieldsResult;
  end;

implementation

function Red: TBGRAPixel;
begin
  Result := BGRA(200, 0, 0, 255);
end;

function Green: TBGRAPixel;
begin
  Result := BGRA(0, 200, 0, 255);
end;

function Sentinel: TBGRAPixel;
begin
  Result := BGRA(255, 0, 255, 255);
end;

function SamePx(const A, B: TBGRAPixel): Boolean;
begin
  Result := (A.red = B.red) and (A.green = B.green) and (A.blue = B.blue) and (A.alpha = B.alpha);
end;

function PxText(const A: TBGRAPixel): string;
begin
  Result := Format('(%d, %d, %d, %d)', [A.red, A.green, A.blue, A.alpha]);
end;

function BytesOfStr(const S: RawByteString): TBytes;
begin
  Result := nil;
  SetLength(Result, Length(S));
  if S <> '' then Move(S[1], Result[0], Length(S));
end;

function StrOfBytes(const B: TBytes; ACount: Integer = -1): RawByteString;
begin
  if ACount < 0 then ACount := Length(B);
  SetLength(Result, ACount);
  if ACount > 0 then Move(B[0], Result[1], ACount);
end;

function FixtureBytes(const AName: string): TBytes;
var
  f: TFileStream;
begin
  Result := nil;
  f := TFileStream.Create(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'tests' + PathDelim +
    'fixtures' + PathDelim + 'rtf' + PathDelim + AName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, f.Size);
    if f.Size > 0 then f.ReadBuffer(Result[0], f.Size);
  finally
    f.Free;
  end;
end;

function PngOfColour(AW, AH: Integer; const AColour: TBGRAPixel): TBytes;
var
  b: TBGRABitmap;
  st: TBytesStream;
begin
  b := TBGRABitmap.Create(AW, AH, AColour);
  st := TBytesStream.Create;
  try
    b.SaveToStreamAs(st, ifPng);
    Result := Copy(st.Bytes, 0, st.Size);
  finally
    st.Free;
    b.Free;
  end;
end;

// as Word writes a picture's bytes: hex digits, 128 to a line
function HexOf(const B: TBytes): RawByteString;
const
  D: array[0..15] of AnsiChar = '0123456789abcdef';
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(B) do
  begin
    if (i > 0) and (i mod 64 = 0) then Result := Result + #13#10;
    Result := Result + D[B[i] shr 4] + D[B[i] and 15];
  end;
end;

function HexToBytes(const S: RawByteString): TBytes;
var
  i, n, h, nib: Integer;
begin
  Result := nil;
  SetLength(Result, Length(S) div 2);
  n := 0;
  nib := -1;
  for i := 1 to Length(S) do
  begin
    case S[i] of
      '0'..'9': h := Ord(S[i]) - Ord('0');
      'a'..'f': h := Ord(S[i]) - Ord('a') + 10;
      'A'..'F': h := Ord(S[i]) - Ord('A') + 10;
    else
      Continue;
    end;
    if nib < 0 then nib := h
    else
    begin
      Result[n] := (nib shl 4) or h;
      Inc(n);
      nib := -1;
    end;
  end;
  SetLength(Result, n);
end;

{ A picture group of a solid PNG of AW x AH pixels shown ATw x ATh twips. }
function Pict(const AColour: TBGRAPixel; AW, AH, ATw, ATh: Integer;
  const AWords: RawByteString = ''): RawByteString;
begin
  Result := '{\pict\pngblip\picw' + IntToStr(AW) + '\pich' + IntToStr(AH) + '\picwgoal' +
    IntToStr(ATw) + '\pichgoal' + IntToStr(ATh) + AWords + #13#10 +
    HexOf(PngOfColour(AW, AH, AColour)) + '}';
end;

// a red one of 40 x 20 pixels (600 x 300 twips)
function RedPict: RawByteString;
begin
  Result := Pict(Red, 40, 20, 600, 300);
end;

function GreenPict: RawByteString;
begin
  Result := Pict(Green, 40, 20, 600, 300);
end;

function EmfPict: RawByteString;
begin
  Result := '{\pict\emfblip\picw1000\pich500\picwgoal600\pichgoal300 ' +
    '0100000084000000000000000000000000000000}';
end;

// a metafile that draws a line, not one bitmap
function WmfPict: RawByteString;
begin
  Result := '{\pict\wmetafile8\picw1000\pich500\picwgoal600\pichgoal300 ' +
    '010009000003220000000000050000000000040000000301080005000000130200000000030000000000}';
end;

function UnknownPict: RawByteString;
begin
  Result := '{\pict\picwgoal600\pichgoal300 ' + HexOf(PngOfColour(40, 20, Red)) + '}';
end;

function Equation(const AInner: RawByteString): RawByteString;
begin
  Result := '{\mmath{\*\moMath{\mr x}}{\mmathPict' + AInner + '}}';
end;

function EmbeddedObject(const AInner: RawByteString): RawByteString;
begin
  Result := '{\object\objemb{\*\objclass Paint.Picture}\objw600\objh300' +
    '{\*\objdata 01050000020000000000}{\result' + AInner + '}}';
end;

function ShapeResult(const AInner: RawByteString; const APib: RawByteString = ''): RawByteString;
begin
  Result := '{\shp{\*\shpinst\shpleft0\shptop0\shpright600\shpbottom300' +
    '{\sp{\sn shapeType}{\sv 75}}';
  if APib <> '' then Result := Result + '{\sp{\sn pib}{\sv ' + APib + '}}';
  Result := Result + '}{\shprslt' + AInner + '}}';
end;

function ShapePib(const APict: RawByteString): RawByteString;
begin
  Result := '{\shp{\*\shpinst{\sp{\sn shapeType}{\sv 75}}{\sp{\sn fFilled}{\sv 1}}' +
    '{\sp{\sn pib}{\sv ' + APict + '}}}}';
end;

function ShpPair(const AFirst, ASecond: RawByteString): RawByteString;
begin
  Result := '{\*\shppict' + AFirst + '}' + #13#10 + '{\nonshppict' + ASecond + '}';
end;

{ A file of two paragraphs: 'ab', the block, 'cd'; then 'second'. }
function InPara(const ABlock: RawByteString): RawByteString;
begin
  Result := '{\rtf1\ansi\deff0{\fonttbl{\f0 Arial;}}' + #13#10 + '\pard ab' + ABlock +
    'cd\par' + #13#10 + '\pard second\par' + #13#10 + '}';
end;

const
  KindNames: array[0..3] of string = ('an equation', 'an embedded object',
    'a shape''s result', 'a shape''s pib');

function OfKind(AKind: Integer; const APict: RawByteString): RawByteString;
begin
  case AKind of
    0: Result := Equation(APict);
    1: Result := EmbeddedObject(APict);
    2: Result := ShapeResult(APict);
  else
    Result := ShapePib(APict);
  end;
end;

{ ---- fixture ---- }

procedure TTyRichKeptPictureTest.SetUp;
begin
  FDocs := TFPList.Create;
  FLayouts := TFPList.Create;
  FDevice := TTyRichTestDevice.Create;
  FLayouter := TTyRichLayouter.Create(FDevice, True);
  FLayouter.BaseFontName := 'Test';
  FLayouter.BaseFontSizeHalfPt := 30;
  FCtl := TTyStyleController.Create(nil);
  FRich := NewProbe;
end;

procedure TTyRichKeptPictureTest.TearDown;
var
  i: Integer;
begin
  FreeAndNil(FRich);
  FreeAndNil(FCtl);
  for i := 0 to FLayouts.Count - 1 do TTyBlockLayout(FLayouts[i]).Release;
  FLayouts.Free;
  FLayouter.Free;
  FLayouter := nil;
  FDevice := nil;
  for i := 0 to FDocs.Count - 1 do TObject(FDocs[i]).Free;
  FDocs.Free;
end;

function TTyRichKeptPictureTest.Doc(const ARtf: RawByteString; AWhole: Boolean): TTyRichDocument;
var
  st: TBytesStream;
begin
  Result := TTyRichDocument.Create;
  FDocs.Add(Result);
  st := TBytesStream.Create(BytesOfStr(ARtf));
  try
    if AWhole then TyRichLoadRtfFull(Result, st) else TyRichLoadRtf(Result, st);
  finally
    st.Free;
  end;
end;

function TTyRichKeptPictureTest.Lay(ADoc: TTyRichDocument; AIndex, AWidth: Integer;
  APPI: Integer): TTyParaLayout;
begin
  Result := FLayouter.LayoutPara(ADoc, AIndex, AWidth, APPI, 1);
  FLayouts.Add(Result);
end;

function TTyRichKeptPictureTest.FragAt(L: TTyParaLayout; APos: Integer): TTyRichFragment;
var
  i: Integer;
begin
  for i := 0 to L.FragmentCount - 1 do
    if (APos >= L.Fragments[i].First) and (APos < L.Fragments[i].First + L.Fragments[i].Count) then
      Exit(L.Fragments[i]);
  Fail(Format('no fragment holds position %d', [APos]));
end;

function TTyRichKeptPictureTest.BoxOf(const ARtf: RawByteString; out AW, AH: Integer;
  APPI: Integer): TTyRichObject;
var
  d: TTyRichDocument;
  L: TTyParaLayout;
  f: TTyRichFragment;
begin
  d := Doc(ARtf);
  Result := d.ObjectAt(2);
  AssertTrue('a kept block at 2', Result is TTyRichOpaque);
  L := Lay(d, 0, 1000, APPI);
  f := FragAt(L, 2);
  AssertTrue('an object fragment', f.Kind = rfkObject);
  AW := f.Width;
  AH := f.Ascent + f.Descent;
end;

function TTyRichKeptPictureTest.MiddleColour(const ARtf: RawByteString): TBGRAPixel;
var
  d: TTyRichDocument;
  L: TTyParaLayout;
  f: TTyRichFragment;
  bmp: TBGRABitmap;
begin
  d := Doc(ARtf);
  L := Lay(d, 0, 1000);
  f := FragAt(L, 2);
  bmp := TBGRABitmap.Create(400, 100, Sentinel);
  try
    L.Paint(bmp, 0, 0, Rect(0, 0, 400, 100), TyRichDefaultPaintStyle, 0, 0);
    Result := bmp.GetPixel(f.X + f.Width div 2, L.Lines[0].Baseline - (f.Ascent div 2));
  finally
    bmp.Free;
  end;
end;

function TTyRichKeptPictureTest.NewProbe: TObjProbe;
begin
  Result := TObjProbe.Create(nil);
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, 400, 300);
  Result.ResetCounts;
end;

procedure TTyRichKeptPictureTest.LoadRtf(const S: RawByteString);
var
  st: TBytesStream;
begin
  st := TBytesStream.Create(BytesOfStr(S));
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  FRich.FinishLoading;
  FRich.UpdateView;
end;

function TTyRichKeptPictureTest.SaveRtf: RawByteString;
var
  st: TBytesStream;
begin
  st := TBytesStream.Create;
  try
    FRich.SaveToStream(st, rfRtf);
    Result := StrOfBytes(st.Bytes, st.Size);
  finally
    st.Free;
  end;
end;

procedure TTyRichKeptPictureTest.PaintAll;
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

// the background work run out and the view painted - without a full repaint: what the work
// made ready is painted again because it asked for it
procedure TTyRichKeptPictureTest.Settle;
var
  n: Integer;
begin
  PaintAll;
  n := 0;
  while FRich.Step and (n < 50) do Inc(n);
  PaintAll;
end;

// the box of the object at APos, from the caret before and after it (client pixels)
function TTyRichKeptPictureTest.BoxRect(APos: TTyRichPos): TRect;
var
  a, b: TRect;
begin
  a := FRich.PositionRect(APos);
  b := FRich.PositionRect(APos + 1);
  Result := Rect(a.Left, a.Top, b.Left, a.Bottom);
end;

{ ---- the tests ---- }

{ Word's own file: paragraph 5 holds an equation whose \mmathPict is a PNG of 1482 x 635
  pixels shown 840 x 360 twips (and a metafile for older readers). It is laid out as a box of
  56 x 24 pixels at 96 PPI, and what is drawn in it is that PNG's pixels - those a picture of
  the same bytes and size gets -, not a placeholder. }
procedure TTyRichKeptPictureTest.TestAWordEquationIsLaidOutAndDrawnAsItsPicture;
var
  d: TTyRichDocument;
  runs: TTyRunArray;
  i, k, para, at: Integer;
  o: TTyRichOpaque;
  L: TTyParaLayout;
  f: TTyRichFragment;
  box: TRect;
  got, want: TBGRABitmap;
  s, hex: RawByteString;
  p0, p1: Integer;
  pic: TTyRichPicture;
  x, y, painted: Integer;
  st: TTyRichPaintStyle;
  bs: TBytesStream;
begin
  d := TTyRichDocument.Create;
  FDocs.Add(d);
  s := StrOfBytes(FixtureBytes('word-unknown.rtf'));
  bs := TBytesStream.Create(BytesOfStr(s));
  try
    TyRichLoadRtf(d, bs);
  finally
    bs.Free;
  end;
  // the paragraph and the place of the equation
  o := nil;
  para := -1;
  at := -1;
  for k := 0 to d.Text.ParaCount - 1 do
  begin
    runs := d.RunsOf(k);
    for i := 0 to High(runs) do
      if (runs[i].Obj is TTyRichOpaque) and
        (Copy(TTyRichOpaque(runs[i].Obj).Bytes, 1, 7) = '{\mmath') then
      begin
        o := TTyRichOpaque(runs[i].Obj);
        para := k;
        at := runs[i].Start;
        Break;
      end;
    if o <> nil then Break;
  end;
  AssertEquals('the equation is in paragraph 5', 5, para);
  L := Lay(d, para, 1000);
  f := FragAt(L, at);
  AssertEquals('840 twips: 56 pixels wide', 56, f.Width);
  AssertEquals('360 twips: 24 pixels tall', 24, f.Ascent + f.Descent);
  // the PNG inside \mmathPict (after its \*\blipuid group), read by the test itself
  p0 := Pos('\pngblip', s);
  AssertTrue('the fixture''s PNG', p0 > 0);
  p0 := Pos('}', Copy(s, p0, MaxInt)) + p0;   // past {\*\blipuid ...}
  p1 := Pos('}', Copy(s, p0, MaxInt)) + p0 - 1;
  hex := Copy(s, p0, p1 - p0);
  pic := TTyRichPicture.Create(rpfPng, HexToBytes(hex), 840, 360);
  pic.AddRef;
  st := TyRichDefaultPaintStyle;
  got := TBGRABitmap.Create(400, 60, Sentinel);
  want := TBGRABitmap.Create(400, 60, Sentinel);
  try
    L.Paint(got, 0, 0, Rect(0, 0, 400, 60), st, 0, 0);
    box := Rect(f.X, L.Lines[0].Baseline - f.Ascent, f.X + f.Width, L.Lines[0].Baseline + f.Descent);
    AssertTrue('the reference is drawn', FLayouter.DrawPicture(want, pic, box, 1, st));
    painted := 0;
    for y := box.Top to box.Bottom - 1 do
      for x := box.Left to box.Right - 1 do
      begin
        AssertTrue(Format('the picture''s pixel at (%d, %d): %s, not %s', [x, y,
          PxText(got.GetPixel(x, y)), PxText(want.GetPixel(x, y))]),
          SamePx(got.GetPixel(x, y), want.GetPixel(x, y)));
        if not SamePx(got.GetPixel(x, y), Sentinel) and
          not SamePx(got.GetPixel(x, y), st.PlaceholderFill) and
          not SamePx(got.GetPixel(x, y), st.PlaceholderFrame) then
          Inc(painted);
      end;
    AssertTrue(Format('the box shows the equation, not a placeholder (%d pixels inked)',
      [painted]), painted > 20);
  finally
    got.Free;
    want.Free;
    pic.Release;
  end;
end;

{ An equation's \mmathPict, an object's \result, a shape's \shprslt and a shape's pib:
  each shows its picture, 40 x 20 pixels in line. }
procedure TTyRichKeptPictureTest.TestEachKindShowsThePictureItCarries;
var
  k, w, h: Integer;
  c: TBGRAPixel;
begin
  for k := 0 to 3 do
  begin
    BoxOf(InPara(OfKind(k, RedPict)), w, h);
    AssertEquals(KindNames[k] + ': its width', 40, w);
    AssertEquals(KindNames[k] + ': its height', 20, h);
    c := MiddleColour(InPara(OfKind(k, RedPict)));
    AssertTrue(KindNames[k] + ': its pixels, not ' + PxText(c), SamePx(Red, c));
  end;
end;

{ The first picture of an object's result, not a later one; a shape's result before its pib
  property, the pib when the result holds no picture. }
procedure TTyRichKeptPictureTest.TestTheFirstPictureAndTheResultBeforePib;
var
  c: TBGRAPixel;
begin
  c := MiddleColour(InPara(EmbeddedObject(RedPict + GreenPict)));
  AssertTrue('the result''s first picture, not ' + PxText(c), SamePx(Red, c));
  c := MiddleColour(InPara(EmbeddedObject('{\rtlch\fcs1 \af0 ' + RedPict + '}' + GreenPict)));
  AssertTrue('the first, also in a group of the result, not ' + PxText(c), SamePx(Red, c));
  c := MiddleColour(InPara(ShapeResult(RedPict, GreenPict)));
  AssertTrue('the shape''s result before its pib, not ' + PxText(c), SamePx(Red, c));
  c := MiddleColour(InPara(ShapeResult('{\*\do\dobxcolumn\dobypara\dodhgt8192}', GreenPict)));
  AssertTrue('a result without a picture: the pib, not ' + PxText(c), SamePx(Green, c));
end;

{ Word's pair of a \*\shppict group and a \nonshppict group: the first of the two that can be
  drawn. }
procedure TTyRichKeptPictureTest.TestOfWordsPairTheFirstThatCanBeDrawn;
var
  k: Integer;
  c: TBGRAPixel;
begin
  for k := 0 to 3 do
  begin
    c := MiddleColour(InPara(OfKind(k, ShpPair(RedPict, GreenPict))));
    AssertTrue(KindNames[k] + ': the first of the pair, not ' + PxText(c), SamePx(Red, c));
    c := MiddleColour(InPara(OfKind(k, ShpPair(EmfPict, GreenPict))));
    AssertTrue(KindNames[k] + ': the second when the first cannot be drawn, not ' + PxText(c),
      SamePx(Green, c));
    c := MiddleColour(InPara(OfKind(k, ShpPair(RedPict, WmfPict))));
    AssertTrue(KindNames[k] + ': the first, the metafile after it unread, not ' + PxText(c),
      SamePx(Red, c));
  end;
end;

{ No picture, a metafile nothing here draws (EMF, a WMF that is not one bitmap), a picture of
  no known format, a pair of two of those, a picture cut off by the end of the file, a result
  of text only: the block is what it was - no width, nothing drawn, no exception -, and saved
  as it came. }
procedure TTyRichKeptPictureTest.TestWhatCannotBeDrawnStaysAsItWas;
const
  Cases: array[0..5] of string = ('no picture', 'an EMF', 'a WMF of a line',
    'an unknown format', 'a pair of neither', 'text only');
var
  k, j, w, h, i: Integer;
  inner, rtf, cut: RawByteString;
  d: TTyRichDocument;
  L: TTyParaLayout;
  bmp: TBGRABitmap;
  runs: TTyRunArray;
  bs: TBytesStream;
begin
  for k := 0 to 3 do
    for j := 0 to High(Cases) do
    begin
      case j of
        0: inner := '{\*\do\dobxcolumn}';
        1: inner := EmfPict;
        2: inner := WmfPict;
        3: inner := UnknownPict;
        4: inner := ShpPair(EmfPict, WmfPict);
      else
        inner := ' some text';
      end;
      rtf := InPara(OfKind(k, inner));
      BoxOf(rtf, w, h);
      AssertEquals(KindNames[k] + ', ' + Cases[j] + ': no width', 0, w);
      AssertTrue(KindNames[k] + ', ' + Cases[j] + ': no picture for it',
        TTyRichOpaque(Doc(rtf).ObjectAt(2)).DisplayPicture = nil);
      d := Doc(rtf);
      bs := TBytesStream.Create;
      try
        TyRichSaveRtf(d, bs);
        AssertTrue(KindNames[k] + ', ' + Cases[j] + ': saved as it came',
          StrOfBytes(bs.Bytes, bs.Size) = rtf);
      finally
        bs.Free;
      end;
    end;
  // the end of the file inside the picture group: whatever the block is, it shows nothing
  for k := 0 to 3 do
  begin
    rtf := InPara(OfKind(k, RedPict));
    cut := Copy(rtf, 1, Pos('89504e', rtf) + 40);
    d := Doc(cut);
    for i := 0 to d.Text.ParaCount - 1 do
    begin
      L := Lay(d, i, 1000);
      bmp := TBGRABitmap.Create(400, 100, Sentinel);
      try
        L.Paint(bmp, 0, 0, Rect(0, 0, 400, 100), TyRichDefaultPaintStyle, 0, 0);
      finally
        bmp.Free;
      end;
      runs := d.RunsOf(i);
      for j := 0 to High(runs) do
        if runs[j].Obj is TTyRichOpaque then
        begin
          AssertTrue(KindNames[k] + ' cut off: no picture',
            TTyRichOpaque(runs[j].Obj).DisplayPicture = nil);
          AssertEquals(KindNames[k] + ' cut off: no width', 0, FragAt(L, runs[j].Start).Width);
        end;
    end;
  end;
end;

{ The picture's own display size - its goal size and its scale words, as a picture's: a PNG
  of 10 x 5 pixels shown 600 x 300 twips is 40 x 20 pixels at 96 PPI, 80 x 40 at 192; scaled
  50 % wide and 200 % tall it is 20 x 40. }
procedure TTyRichKeptPictureTest.TestTheSizeIsThePicturesOwnDisplaySize;
var
  k, w, h: Integer;
begin
  for k := 0 to 3 do
  begin
    BoxOf(InPara(OfKind(k, Pict(Red, 10, 5, 600, 300))), w, h);
    AssertEquals(KindNames[k] + ': the goal width, not the pixels', 40, w);
    AssertEquals(KindNames[k] + ': the goal height, not the pixels', 20, h);
    BoxOf(InPara(OfKind(k, Pict(Red, 10, 5, 600, 300))), w, h, 192);
    AssertEquals(KindNames[k] + ' at 192 PPI: its width', 80, w);
    AssertEquals(KindNames[k] + ' at 192 PPI: its height', 40, h);
    BoxOf(InPara(OfKind(k, Pict(Red, 10, 5, 600, 300, '\picscalex50\picscaley200'))), w, h);
    AssertEquals(KindNames[k] + ' scaled: its width', 20, w);
    AssertEquals(KindNames[k] + ' scaled: its height', 40, h);
  end;
end;

{ A picture wider than the text: the block's box is where and how large a picture of the same
  size is in the same paragraph at the same width. }
procedure TTyRichKeptPictureTest.TestWiderThanTheTextAsAPictureIs;
var
  k: Integer;
  dk, dp: TTyRichDocument;
  Lk, Lp: TTyParaLayout;
  fk, fp: TTyRichFragment;
begin
  dp := Doc(InPara(Pict(Red, 40, 20, 30000, 300)));
  AssertTrue('the reference is a picture', dp.ObjectAt(2) is TTyRichPicture);
  Lp := Lay(dp, 0, 300);
  fp := FragAt(Lp, 2);
  for k := 0 to 3 do
  begin
    dk := Doc(InPara(OfKind(k, Pict(Red, 40, 20, 30000, 300))));
    Lk := Lay(dk, 0, 300);
    fk := FragAt(Lk, 2);
    AssertEquals(KindNames[k] + ': its width as a picture''s', fp.Width, fk.Width);
    AssertEquals(KindNames[k] + ': its height as a picture''s', fp.Ascent, fk.Ascent);
    AssertEquals(KindNames[k] + ': its place as a picture''s', fp.X, fk.X);
    AssertEquals(KindNames[k] + ': its lines as a picture''s', Lp.LineCount, Lk.LineCount);
    AssertEquals(KindNames[k] + ': the block as wide', Lp.Width, Lk.Width);
  end;
end;

{ Not at load; once for each object when it is first measured; not again for another layout
  of it, nor for a paint; a copy of it is an object of its own. }
procedure TTyRichKeptPictureTest.TestLookedForOncePerObjectAndNotAtLoad;
var
  n0: Int64;
  d: TTyRichDocument;
  L: TTyParaLayout;
  bmp: TBGRABitmap;
  rtf: RawByteString;
  i: Integer;
begin
  rtf := InPara(Equation(RedPict) + EmbeddedObject(GreenPict)) ;
  n0 := TyRichKeptPictureLookups;
  d := Doc(rtf);
  Doc(rtf, True);
  AssertEquals('nothing looked for at load', n0, TyRichKeptPictureLookups);
  L := Lay(d, 0, 1000);
  AssertEquals('once for each of the two blocks', n0 + 2, TyRichKeptPictureLookups);
  bmp := TBGRABitmap.Create(400, 100, Sentinel);
  try
    for i := 1 to 3 do
    begin
      L.Paint(bmp, 0, 0, Rect(0, 0, 400, 100), TyRichDefaultPaintStyle, 0, 0);
      FLayouter.Clear;
      L := Lay(d, 0, 1000 - i);
      L := Lay(d, 0, 1000 - i, 192);
    end;
  finally
    bmp.Free;
  end;
  AssertEquals('not again for other layouts and paints', n0 + 2, TyRichKeptPictureLookups);
  // through the control: its load and layout, its paints, the background work, caret moves
  n0 := TyRichKeptPictureLookups;
  LoadRtf(rtf);
  Settle;
  AssertEquals('the control: once for each', n0 + 2, TyRichKeptPictureLookups);
  for i := 1 to 3 do
  begin
    FRich.SelStart := i;
    FRich.RedrawAll;
    Settle;
  end;
  AssertEquals('the control: not per paint', n0 + 2, TyRichKeptPictureLookups);
end;

{ Opened and saved: byte for byte what came in. An insert before it in its paragraph keeps
  its bytes verbatim. }
procedure TTyRichKeptPictureTest.TestOpenedAndSavedAsItCameAndAnInsertKeepsItsBytes;
var
  k: Integer;
  block, rtf, got: RawByteString;
begin
  for k := 0 to 4 do
  begin
    if k = 4 then block := Equation(ShpPair(RedPict, WmfPict))
    else block := OfKind(k, RedPict);
    rtf := InPara(block);
    LoadRtf(rtf);
    Settle;
    AssertTrue(IntToStr(k) + ': saved as it came', SaveRtf = rtf);
    FRich.SelStart := 0;
    FRich.Key8('x');
    got := SaveRtf;
    AssertTrue(IntToStr(k) + ': typed', Pos('xab', got) > 0);
    AssertTrue(IntToStr(k) + ': the block''s bytes kept', Pos(block, got) > 0);
  end;
end;

{ A file read on demand gives what reading it whole gives: the same blocks, the same boxes. }
procedure TTyRichKeptPictureTest.TestReadOnDemandIsReadWhole;
var
  k: Integer;
  rtf: RawByteString;
  a, b: TTyRichDocument;
  fa, fb: TTyRichFragment;
begin
  for k := 0 to 3 do
  begin
    rtf := InPara(OfKind(k, RedPict) + ' and ' + OfKind(k, ShpPair(EmfPict, GreenPict)));
    a := Doc(rtf);
    b := Doc(rtf, True);
    AssertEquals(KindNames[k] + ': paragraphs', b.Text.ParaCount, a.Text.ParaCount);
    AssertTrue(KindNames[k] + ': the text', a.Text.GetText(0, a.Text.Length) =
      b.Text.GetText(0, b.Text.Length));
    AssertTrue(KindNames[k] + ': the first block''s bytes',
      TTyRichOpaque(a.ObjectAt(2)).Bytes = TTyRichOpaque(b.ObjectAt(2)).Bytes);
    fa := FragAt(Lay(a, 0, 1000), 8);
    fb := FragAt(Lay(b, 0, 1000), 8);
    AssertEquals(KindNames[k] + ': the second block''s box', fb.Width, fa.Width);
    AssertEquals(KindNames[k] + ': it shows', 40, fa.Width);
  end;
end;

{ One caret step across it; a click on it selects it - its frame, no handles - and it shows its
  picture once the background work has made it ready. }
procedure TTyRichKeptPictureTest.TestOneCaretStepAClickAFrameNoHandles;
var
  k: Integer;
  box: TRect;
  c: TPoint;
  st: TTyRichPaintStyle;
  rs: TTyRichHandleRects;
begin
  for k := 0 to 3 do
  begin
    LoadRtf(InPara(OfKind(k, RedPict)));
    FRich.SelStart := 2;
    Settle;
    box := BoxRect(2);
    AssertEquals(KindNames[k] + ': the box''s width', 40, box.Right - box.Left);
    c := Point((box.Left + box.Right) div 2, box.Bottom - 10);
    AssertTrue(KindNames[k] + ': its picture, not ' + PxText(FRich.Surf.GetPixel(c.X, c.Y)),
      SamePx(Red, FRich.Surf.GetPixel(c.X, c.Y)));
    FRich.Press(VK_RIGHT, []);
    AssertEquals(KindNames[k] + ': one step across it', 3, FRich.SelStart);
    FRich.Press(VK_LEFT, []);
    AssertEquals(KindNames[k] + ': one step back', 2, FRich.SelStart);
    FRich.PressAt(c.X, c.Y);
    FRich.ReleaseAt(c.X, c.Y);
    PaintAll;
    AssertEquals(KindNames[k] + ': a click selects it: start', 2, FRich.SelStart);
    AssertEquals(KindNames[k] + ': a click selects it: length', 1, FRich.SelLength);
    AssertFalse(KindNames[k] + ': no handles', FRich.Handles(rs));
    st := FRich.Style;
    AssertTrue(KindNames[k] + ': the frame', SamePx(st.ObjectFrame,
      FRich.Surf.GetPixel(box.Left, c.Y)));
    AssertTrue(KindNames[k] + ': the frame on the right', SamePx(st.ObjectFrame,
      FRich.Surf.GetPixel(box.Right - 1, c.Y)));
  end;
end;

{ A resize asked from code is refused by the command's own check: the block cannot be shown
  at another size, and nothing changes. }
procedure TTyRichKeptPictureTest.TestResizeIsRefused;
var
  k: Integer;
  cmd: TTyRichResizeObject;
  rtf: RawByteString;
  depth: Integer;
begin
  for k := 0 to 3 do
  begin
    rtf := InPara(OfKind(k, RedPict));
    LoadRtf(rtf);
    Settle;
    AssertFalse(KindNames[k] + ': it cannot be resized', FRich.Document.ObjectAt(2).CanResize);
    cmd := TTyRichResizeObject.Create(2, 1200, 600);
    try
      AssertFalse(KindNames[k] + ': the resize is refused', cmd.CanExecute(FRich.Document));
    finally
      cmd.Free;
    end;
    depth := FRich.Document.UndoDepth;
    AssertFalse(KindNames[k] + ': executed, it does nothing',
      FRich.Document.Execute(TTyRichResizeObject.Create(2, 1200, 600)));
    AssertEquals(KindNames[k] + ': no step', depth, FRich.Document.UndoDepth);
    AssertTrue(KindNames[k] + ': still the block', FRich.Document.ObjectAt(2) is TTyRichOpaque);
    AssertTrue(KindNames[k] + ': saved as it came', SaveRtf = rtf);
  end;
end;

{ Deleted whole and brought back by undo; copied and pasted into the same document and into
  another: the block arrives as its bytes, and shows its picture there too. }
procedure TTyRichKeptPictureTest.TestDeleteUndoCopyAndPaste;
var
  k, w, h: Integer;
  block, rtf: RawByteString;
  other, keep: TObjProbe;
  o: TTyRichObject;
  saved: RawByteString;
  d: TTyRichDocument;
begin
  for k := 0 to 3 do
  begin
    block := OfKind(k, RedPict);
    rtf := InPara(block);
    LoadRtf(rtf);
    Settle;
    FRich.SelStart := 2;
    FRich.SelLength := 1;
    FRich.Press(VK_DELETE, []);
    AssertTrue(KindNames[k] + ': deleted', FRich.Document.Text.GetText(0, 4) = 'abcd');
    FRich.Undo;
    AssertTrue(KindNames[k] + ': undone', FRich.Document.ObjectAt(2) is TTyRichOpaque);
    AssertTrue(KindNames[k] + ': saved as it came after the undo', SaveRtf = rtf);
    // copied, pasted after 'cd'
    FRich.SelStart := 2;
    FRich.SelLength := 1;
    FRich.CopyToClipboard;
    AssertTrue(KindNames[k] + ': its bytes on the clipboard', Pos(block, FRich.ClipRtf) > 0);
    FRich.SelStart := 5;
    FRich.SelLength := 0;
    FRich.PasteFromClipboard;
    o := FRich.Document.ObjectAt(5);
    AssertTrue(KindNames[k] + ': pasted as the block', o is TTyRichOpaque);
    AssertTrue(KindNames[k] + ': its bytes', TTyRichOpaque(o).Bytes = block);
    Settle;
    w := BoxRect(5).Right - BoxRect(5).Left;
    AssertEquals(KindNames[k] + ': the pasted one shows its picture', 40, w);
    // into another document
    other := NewProbe;
    keep := FRich;
    try
      FRich := other;
      FRich.Lines.Text := 'xyz';
      FRich.ClipRtf := keep.ClipRtf;
      FRich.SelStart := 1;
      FRich.PasteFromClipboard;
      o := FRich.Document.ObjectAt(1);
      AssertTrue(KindNames[k] + ': into another document: the block', o is TTyRichOpaque);
      AssertTrue(KindNames[k] + ': into another document: its bytes',
        TTyRichOpaque(o).Bytes = block);
      Settle;
      h := BoxRect(1).Right - BoxRect(1).Left;
      AssertEquals(KindNames[k] + ': into another document: it shows', 40, h);
      // a document of no file: the block is written from the model, as its bytes
      saved := SaveRtf;
      AssertTrue(KindNames[k] + ': into another document: saved as its bytes',
        Pos(block, saved) > 0);
      d := Doc(saved);
      AssertTrue(KindNames[k] + ': read back: the block', (d.ObjectAt(1) is TTyRichOpaque) and
        (TTyRichOpaque(d.ObjectAt(1)).Bytes = block));
      AssertTrue(KindNames[k] + ': read back: nothing beside it',
        d.Text.GetText(0, d.Text.ParaLength(0)) = FRich.Document.Text.GetText(0,
        FRich.Document.Text.ParaLength(0)));
    finally
      FRich := keep;
      other.Free;
    end;
  end;
end;

{ A block in a shown field's result (a link around an embedded object): the same picture,
  selected by a click; read-only there - it cannot be deleted alone -, and the file saved as
  it came. }
procedure TTyRichKeptPictureTest.TestInAShownFieldsResult;
var
  rtf, block: RawByteString;
  at, depth: Integer;
  box: TRect;
  c: TPoint;
begin
  block := EmbeddedObject(RedPict);
  rtf := InPara('{\field{\*\fldinst HYPERLINK "https://example.com/"}{\fldrslt ' + block + '}}');
  LoadRtf(rtf);
  at := 2;
  while (at < 8) and not (FRich.Document.ObjectAt(at) is TTyRichOpaque) do Inc(at);
  AssertTrue('the block between the field''s marks',
    (FRich.Document.ObjectAt(at) is TTyRichOpaque) and
    (FRich.Document.ObjectAt(at - 1) is TTyRichFieldMark) and
    (FRich.Document.ObjectAt(at + 1) is TTyRichFieldMark));
  Settle;
  box := BoxRect(at);
  AssertEquals('it shows its picture: the width', 40, box.Right - box.Left);
  c := Point((box.Left + box.Right) div 2, box.Bottom - 10);
  AssertTrue('its pixels, not ' + PxText(FRich.Surf.GetPixel(c.X, c.Y)),
    SamePx(Red, FRich.Surf.GetPixel(c.X, c.Y)));
  FRich.PressAt(c.X, c.Y);
  FRich.ReleaseAt(c.X, c.Y);
  AssertEquals('a click selects it: start', at, FRich.SelStart);
  AssertEquals('a click selects it: length', 1, FRich.SelLength);
  AssertFalse('read-only: it cannot be deleted alone', FRich.Document.CanChange(at, 1));
  depth := FRich.Document.UndoDepth;
  FRich.Press(VK_DELETE, []);
  AssertEquals('the delete is refused', depth, FRich.Document.UndoDepth);
  AssertTrue('still there', FRich.Document.ObjectAt(at) is TTyRichOpaque);
  AssertTrue('saved as it came', SaveRtf = rtf);
end;

initialization
  RegisterTest(TTyRichKeptPictureTest);
end.
