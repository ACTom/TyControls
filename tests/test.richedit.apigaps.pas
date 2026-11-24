unit test.richedit.apigaps;

{ What code can now make of TTyRichEdit's content outside tables: the list's level, start and
  a bullet of its own text, tab stops with their alignment and leader, a paragraph's shading,
  any line spacing multiple, half-point sizes, the page set-up, the document's default formats
  and its own ground (Word's page colour), the user's paragraph spacing, and a picture from a
  graphic or an image list as a command.

  Each member: set it (one undo step), save, read the file back - the value is there - and
  undo: the file saved again is the file as it was, byte for byte. What is drawn: a leader, a
  paragraph's shading and the document's ground, automatic text over them in the colour that
  stands out from them (the rule a highlight already had). Line heights against Word's own
  numbers (real fonts: Windows only).

  Headless: the edit suite's probe (the test device), no window, no clipboard. }

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  Classes, SysUtils, Math, fpcunit, testregistry, Controls, Graphics, LCLType, ImgList,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Controller, tyControls.RichEdit.Text, tyControls.RichEdit.Model,
  tyControls.RichEdit.Commands, tyControls.RichEdit.Layout, tyControls.RichEdit.RtfRead,
  tyControls.RichEdit.Attrs, tyControls.RichEdit,
  test.richedit.layoutdevice, test.richedit.control, test.richedit.edit;

type
  TTyRichApiGapsTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FRich: TEditProbe;
    FBack: TEditProbe;
    FDocs: TFPList;
    FLayouts: TFPList;
    FLayouter: TTyRichLayouter;
    FOriginal: TBytes;
    function NewProbe: TEditProbe;
    // AText into FRich as RTF; the original bytes kept (and checked: an open-save is them)
    procedure Load(const AText: RawByteString);
    function Saved(AProbe: TEditProbe = nil): TBytes;
    // ABytes read into a second probe (FBack)
    function ReadBack(const ABytes: TBytes): TTyRichDocument;
    function PF(ADoc: TTyRichDocument; AIndex: Integer): TTyParaFormat;
    function CF(ADoc: TTyRichDocument; AIndex: Integer): TTyCharFormat;
    // one undo of FRich, and the file it saves is the original
    procedure UndoGivesTheFileBack(const AWhat: string);
    procedure Sel(AStart, ALen: TTyRichPos);
    procedure PaintAll;
    function Lay(ADoc: TTyRichDocument; AIndex, AWidth: Integer): TTyParaLayout;
    procedure Need(const AFonts: array of string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    // each member: set, save, read back, undo to the file's own bytes
    procedure TestListLevelRoundTrips;
    procedure TestListStartRoundTrips;
    procedure TestBulletTextRoundTripsAndIsDrawn;
    procedure TestSetTabRoundTrips;
    procedure TestShadingRoundTrips;
    procedure TestSizeFRoundTrips;
    procedure TestPageSetupRoundTrips;
    procedure TestDefaultFormatsRoundTrip;
    procedure TestDocumentColorRoundTrips;
    procedure TestApplyParagraphSpacingRoundTrips;
    procedure TestLineSpacingMultipleRoundTrips;
    procedure TestPictureFromAGraphic;
    procedure TestPictureFromAnImageList;
    // what is drawn
    procedure TestTabLeaderIsDrawn;
    procedure TestParagraphShadingIsDrawnAndAutomaticTextContrasts;
    procedure TestDocumentColorWinsOverTheTheme;
    // Word's files and Word's numbers
    procedure TestWordsShadingAndBackgroundAreRead;
    procedure TestWord16sPageColourFile;
    procedure TestAWordFilesHeaderChangesOnlyWhereTheSettingsAre;
    procedure TestAnyMultipleIsLaidOutAsWordLaysItOut;
    procedure TestALazyFileKeepsItsLookWhenTheDefaultsChange;
  end;

implementation

const
  BS = #92;
  // a WordPad-like file: Arial as \f0, the page, two paragraphs
  CBase: RawByteString =
    '{\rtf1\ansi\ansicpg1252\deff0{\fonttbl{\f0\fnil\fcharset0 Arial;}}'#13#10 +
    '{\colortbl ;\red255\green0\blue0;}'#13#10 +
    '\paperw12240\paperh15840\margl1800\margr1800\viewkind4\uc1 '#13#10 +
    '\pard\f0\fs24 One\par'#13#10 + '\pard Two\par'#13#10 + '}'#13#10;
  // a numbered paragraph as WordPad writes one
  CList: RawByteString =
    '{\rtf1\ansi\ansicpg1252\deff0{\fonttbl{\f0\fnil\fcharset0 Arial;}}'#13#10 +
    '\viewkind4\uc1 '#13#10 +
    '\pard{\pntext\f0 1.\tab}{\*\pn\pnlvlbody\pnf0\pnindent0\pnstart1\pndec{\pntxta.}}'#13#10 +
    '\fi-360\li720\f0\fs24 One\par'#13#10 + '\pard Two\par'#13#10 + '}'#13#10;
  // Word's page colour (RGB CC C0 DA) and a paragraph shaded with a pattern
  CWordBack: RawByteString =
    '{\rtf1\ansi\ansicpg1252\deff0{\fonttbl{\f0\fnil\fcharset0 Arial;}}'#13#10 +
    '{\colortbl ;\red0\green0\blue0;\red255\green255\blue0;}'#13#10 +
    '\paperw11906\paperh16838\margl1800\margr1800\viewkind1\viewbksp1'#13#10 +
    '{\*\background {\shp{\*\shpinst\shpleft0\shptop0\shpright0\shpbottom0\shpfhdr0\shpbxmargin' +
    '\shpbymargin\shpwr0\shpwrk0\shpfblwtxt1\shpz0\shplid1025{\sp{\sn shapeType}{\sv 1}}' +
    '{\sp{\sn fFlipH}{\sv 0}}{\sp{\sn fFlipV}{\sv 0}}{\sp{\sn fillColor}{\sv 14336204}}' +
    '{\sp{\sn fFilled}{\sv 1}}{\sp{\sn lineWidth}{\sv 0}}{\sp{\sn fLine}{\sv 0}}' +
    '{\sp{\sn bWMode}{\sv 9}}{\sp{\sn fBackground}{\sv 1}}}}}'#13#10 +
    '\pard\cbpat2\f0\fs24 Yellow\par'#13#10 +
    '\pard\shading5000\cfpat1 Half black\par'#13#10 +
    '\pard Plain\par'#13#10 + '}'#13#10;
  // two Han characters, UTF-8
  CHan = #$E6#$B1#$89#$E5#$AD#$97;

{ The page colour's group as Word 16 writes it (a new document given a page colour, saved as
  RTF): no \viewbksp, the shape alone; AFill a COLORREF. }
function CWord16Back(AFill: Integer): RawByteString;
begin
  Result := '{\*\background {\shp{\*\shpinst\shpleft0\shptop0\shpright0\shpbottom0\shpfhdr0' +
    '\shpbxmargin\shpbxignore\shpbymargin\shpbyignore\shpwr0\shpwrk0\shpfblwtxt1\shpz0' +
    '\shplid1025'#13#10'{\sp{\sn shapeType}{\sv 1}}{\sp{\sn fFlipH}{\sv 0}}{\sp{\sn fFlipV}{\sv 0}}' +
    '{\sp{\sn fillColor}{\sv ' + IntToStr(AFill) + '}}{\sp{\sn fFilled}{\sv 1}}' +
    '{\sp{\sn lineWidth}{\sv 0}}{\sp{\sn fLine}{\sv 0}}{\sp{\sn bWMode}{\sv 9}}' +
    '{\sp{\sn fBackground}{\sv 1}}'#13#10'{\sp{\sn fLayoutInCell}{\sv 1}}}}}';
end;

function RawBytes(const S: RawByteString): TBytes;
begin
  Result := nil;
  SetLength(Result, Length(S));
  if Length(S) > 0 then Move(S[1], Result[0], Length(S));
end;

function AsRaw(const B: TBytes): RawByteString;
begin
  Result := '';
  SetLength(Result, Length(B));
  if Length(B) > 0 then Move(B[0], Result[1], Length(B));
end;

function SameBytes(const A, B: TBytes): Boolean;
begin
  Result := (Length(A) = Length(B)) and ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A)));
end;

function Has(const B: TBytes; const S: RawByteString): Boolean;
begin
  Result := Pos(S, AsRaw(B)) > 0;
end;

function Sentinel: TBGRAPixel;
begin
  Result := BGRA(255, 0, 255, 255);
end;

function SamePx(const A, B: TBGRAPixel): Boolean;
begin
  Result := (A.red = B.red) and (A.green = B.green) and (A.blue = B.blue) and
    (A.alpha = B.alpha);
end;

function PxOf(AColor: TColor): TBGRAPixel;
begin
  Result := ColorToBGRA(ColorToRGB(AColor));
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

{$IFDEF MSWINDOWS}
type
  TFontQuery = record
    Height, Width, Escapement, Orientation, Weight: LongInt;
    Italic, Underline, StrikeOut, CharSet, OutPrecision, ClipPrecision, Quality,
      PitchAndFamily: Byte;
    FaceName: array[0..31] of WideChar;
  end;

function TyGetDC(AWnd: PtrUInt): PtrUInt; stdcall; external 'user32' name 'GetDC';
function TyReleaseDC(AWnd, ADC: PtrUInt): LongInt; stdcall; external 'user32' name 'ReleaseDC';
function TyEnumFontFamiliesExW(ADC: PtrUInt; var AFont: TFontQuery; AProc: Pointer;
  AData: PtrInt; AFlags: LongWord): LongInt; stdcall; external 'gdi32' name 'EnumFontFamiliesExW';

function FontFound(AFont, AMetric: Pointer; AType: LongWord; AData: PtrInt): LongInt; stdcall;
begin
  PBoolean(AData)^ := True;
  Result := 0;
end;

function FontInstalled(const AName: string): Boolean;
var
  q: TFontQuery;
  dc: PtrUInt;
  w: UnicodeString;
  found: Boolean;
begin
  FillChar(q, SizeOf(q), 0);
  q.CharSet := 1;
  w := UnicodeString(AName);
  Move(PWideChar(w)^, q.FaceName[0], Min(Length(w), 31) * SizeOf(WideChar));
  found := False;
  dc := TyGetDC(0);
  try
    TyEnumFontFamiliesExW(dc, q, @FontFound, PtrInt(@found), 0);
  finally
    TyReleaseDC(0, dc);
  end;
  Result := found;
end;
{$ENDIF}

{ ---- fixtures ---- }

procedure TTyRichApiGapsTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FDocs := TFPList.Create;
  FLayouts := TFPList.Create;
  FRich := NewProbe;
  FBack := nil;
  FLayouter := TTyRichLayouter.Create(TTyRichTestDevice.Create, True);
  FLayouter.BaseFontName := 'Test';
  FLayouter.BaseFontSizeHalfPt := 30;
end;

procedure TTyRichApiGapsTest.TearDown;
var
  i: Integer;
begin
  for i := 0 to FLayouts.Count - 1 do TTyBlockLayout(FLayouts[i]).Release;
  FLayouts.Free;
  FreeAndNil(FLayouter);
  for i := 0 to FDocs.Count - 1 do TObject(FDocs[i]).Free;
  FDocs.Free;
  FreeAndNil(FBack);
  FreeAndNil(FRich);
  FreeAndNil(FCtl);
end;

function TTyRichApiGapsTest.NewProbe: TEditProbe;
begin
  Result := TEditProbe.Create(nil);
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, 400, 300);
  Result.ResetCounts;
end;

procedure TTyRichApiGapsTest.Load(const AText: RawByteString);
var
  st: TBytesStream;
begin
  FOriginal := RawBytes(AText);
  st := TBytesStream.Create(FOriginal);
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  FRich.FinishLoading;
  FRich.UpdateView;
  AssertTrue('opened and saved: the file''s own bytes', SameBytes(FOriginal, Saved));
end;

function TTyRichApiGapsTest.Saved(AProbe: TEditProbe): TBytes;
var
  st: TMemoryStream;
begin
  if AProbe = nil then AProbe := FRich;
  st := TMemoryStream.Create;
  try
    AProbe.SaveToStream(st, rfRtf);
    Result := nil;
    SetLength(Result, st.Size);
    if st.Size > 0 then Move(st.Memory^, Result[0], st.Size);
  finally
    st.Free;
  end;
end;

function TTyRichApiGapsTest.ReadBack(const ABytes: TBytes): TTyRichDocument;
var
  st: TBytesStream;
begin
  FreeAndNil(FBack);
  FBack := NewProbe;
  st := TBytesStream.Create(ABytes);
  try
    FBack.LoadFromStream(st);
  finally
    st.Free;
  end;
  FBack.FinishLoading;
  Result := FBack.Document;
end;

function TTyRichApiGapsTest.PF(ADoc: TTyRichDocument; AIndex: Integer): TTyParaFormat;
begin
  Result := ADoc.Formats.ParaFormat(ADoc.ParaFormatOf(AIndex));
end;

function TTyRichApiGapsTest.CF(ADoc: TTyRichDocument; AIndex: Integer): TTyCharFormat;
begin
  Result := ADoc.Formats.CharFormat(ADoc.RunsOf(AIndex)[0].Format);
end;

procedure TTyRichApiGapsTest.UndoGivesTheFileBack(const AWhat: string);
begin
  AssertTrue(AWhat + ': a step to undo', FRich.Document.CanUndo);
  FRich.Undo;
  AssertTrue(AWhat + ': undone, the file''s own bytes again: ' + AsRaw(Saved),
    SameBytes(FOriginal, Saved));
end;

procedure TTyRichApiGapsTest.Sel(AStart, ALen: TTyRichPos);
begin
  FRich.SelStart := AStart;
  FRich.SelLength := ALen;
end;

procedure TTyRichApiGapsTest.PaintAll;
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

function TTyRichApiGapsTest.Lay(ADoc: TTyRichDocument; AIndex, AWidth: Integer): TTyParaLayout;
begin
  FLayouter.Clear;
  Result := FLayouter.LayoutPara(ADoc, AIndex, AWidth, 96, 1);
  FLayouts.Add(Result);
end;

procedure TTyRichApiGapsTest.Need(const AFonts: array of string);
var
  i: Integer;
begin
  {$IFDEF MSWINDOWS}
  for i := 0 to High(AFonts) do
    if not FontInstalled(AFonts[i]) then Ignore('the font ' + AFonts[i] + ' is not installed');
  {$ELSE}
  i := 0;
  Ignore('real fonts with Word''s numbers: Windows only');
  {$ENDIF}
end;

{ ---- each member ---- }

procedure TTyRichApiGapsTest.TestListLevelRoundTrips;
var
  d: TTyRichDocument;
  n: Integer;
begin
  Load(CList);
  Sel(0, 0);
  AssertEquals('read: the outermost', 0, FRich.Paragraph.ListLevel);
  n := FRich.Document.UndoDepth;
  FRich.Paragraph.ListLevel := 2;
  AssertEquals('one step', n + 1, FRich.Document.UndoDepth);
  AssertEquals('read back here', 2, FRich.Paragraph.ListLevel);
  AssertEquals('the kind stays', Ord(lkDecimal), Ord(PF(FRich.Document, 0).List.Kind));
  d := ReadBack(Saved);
  AssertEquals('the file: its level', 2, PF(d, 0).List.Level);
  AssertEquals('the file: its kind', Ord(lkDecimal), Ord(PF(d, 0).List.Kind));
  UndoGivesTheFileBack('ListLevel');
end;

procedure TTyRichApiGapsTest.TestListStartRoundTrips;
var
  d: TTyRichDocument;
begin
  Load(CList);
  Sel(0, 0);
  AssertEquals('read', 1, FRich.Paragraph.ListStart);
  FRich.Paragraph.ListStart := 7;
  AssertEquals('NumberingStart is the same', 7, FRich.Paragraph.NumberingStart);
  d := ReadBack(Saved);
  AssertEquals('the file: it starts at 7', 7, PF(d, 0).List.StartAt);
  UndoGivesTheFileBack('ListStart');
end;

procedure TTyRichApiGapsTest.TestBulletTextRoundTripsAndIsDrawn;
const
  Arrow = #$E2#$86#$92;   // U+2192
var
  d: TTyRichDocument;
  L: TTyParaLayout;
  bmp: TBGRABitmap;
  st: TTyRichPaintStyle;
begin
  Load(CBase);
  Sel(0, 0);
  FRich.Paragraph.BulletText := Arrow;
  AssertEquals('a bullet item now', Ord(lkBullet), Ord(PF(FRich.Document, 0).List.Kind));
  AssertEquals('read back here', Arrow, FRich.Paragraph.BulletText);
  AssertTrue('the default hanging indent', PF(FRich.Document, 0).LeftIndent = CTyListLeftIndent);
  d := ReadBack(Saved);
  AssertEquals('the file: a bullet', Ord(lkBullet), Ord(PF(d, 0).List.Kind));
  AssertEquals('the file: its own text', Arrow, PF(d, 0).List.Bullet);
  // (nothing of its words kept: only the reference to the file's list table)
  AssertEquals('the file: only the list''s \ls and \ilvl kept', 2, PF(d, 0).Extra.Count);
  // drawn: the marker is the bullet's own text
  L := Lay(FRich.Document, 0, 1000);
  AssertTrue('a marker', L.HasMarker);
  AssertEquals('its text', Arrow, L.Marker.Text);
  bmp := TBGRABitmap.Create(200, 30, Sentinel);
  try
    st := TyRichDefaultPaintStyle;
    TTyRichTestDevice(FLayouter.Device).DrawLog.Clear;
    L.Paint(bmp, 0, 0, Rect(0, 0, 200, 30), st, 0, 0);
    // (the text, then the marker)
    AssertEquals('drawn: the marker after the text', 2, TTyRichTestDevice(FLayouter.Device).DrawLog.Count);
    AssertEquals('the marker: the bullet''s own text', Arrow,
      Copy(TTyRichTestDevice(FLayouter.Device).DrawLog[1], 1, Length(Arrow)));
  finally
    bmp.Free;
  end;
  UndoGivesTheFileBack('BulletText');
end;

procedure TTyRichApiGapsTest.TestSetTabRoundTrips;
var
  d: TTyRichDocument;
  t: TTyTabStops;
begin
  Load(CBase);
  Sel(0, 0);
  FRich.Paragraph.SetTab(0, 72, rtaRight, rtlDot);
  t := PF(FRich.Document, 0).Tabs;
  AssertEquals('one stop', 1, Length(t));
  AssertEquals('at 1 inch', 1440, t[0].Position);
  d := ReadBack(Saved);
  t := PF(d, 0).Tabs;
  AssertEquals('the file: one stop', 1, Length(t));
  AssertEquals('the file: at 1 inch', 1440, t[0].Position);
  AssertEquals('the file: right-aligned', Ord(ttaRight), Ord(t[0].Align));
  AssertEquals('the file: dots', Ord(ttlDot), Ord(t[0].Leader));
  UndoGivesTheFileBack('SetTab');
end;

procedure TTyRichApiGapsTest.TestShadingRoundTrips;
var
  d: TTyRichDocument;
  b: TBytes;
begin
  Load(CBase);
  Sel(0, 0);
  AssertEquals('none', clNone, FRich.Paragraph.Shading);
  FRich.Paragraph.Shading := clYellow;
  AssertEquals('read back here', clYellow, FRich.Paragraph.Shading);
  b := Saved;
  AssertTrue('written as the fill', Has(b, BS + 'cbpat2'));
  AssertTrue('its colour in the table', Has(b, BS + 'red255' + BS + 'green255' + BS + 'blue0;'));
  d := ReadBack(b);
  AssertEquals('the file: yellow', clYellow, PF(d, 0).Shading);
  AssertEquals('the file: nothing of it kept as words', 0, PF(d, 0).Extra.Count);
  AssertEquals('the next paragraph: none', clNone, PF(d, 1).Shading);
  UndoGivesTheFileBack('Shading');
  // written clDefault or clWindow: none, as a highlight
  FRich.Paragraph.Shading := clRed;
  FRich.Paragraph.Shading := clWindow;
  AssertEquals('clWindow: none', clNone, FRich.Paragraph.Shading);
end;

procedure TTyRichApiGapsTest.TestSizeFRoundTrips;
var
  d: TTyRichDocument;
begin
  Load(CBase);
  Sel(0, 3);
  AssertEquals('12 pt', 12.0, FRich.SelAttributes.SizeF, 0);
  FRich.SelAttributes.SizeF := 10.5;
  AssertEquals('10.5 pt', 10.5, FRich.SelAttributes.SizeF, 0);
  AssertEquals('Size says 10, as Delphi''s', 10, FRich.SelAttributes.Size);
  AssertEquals('half points', 21, CF(FRich.Document, 0).SizeHalfPt);
  d := ReadBack(Saved);
  AssertEquals('the file: 10.5 pt', 21, CF(d, 0).SizeHalfPt);
  UndoGivesTheFileBack('SizeF');
  // to the nearest half point
  Sel(0, 3);
  FRich.SelAttributes.SizeF := 9.3;
  AssertEquals('9.3: 9.5', 19, CF(FRich.Document, 0).SizeHalfPt);
end;

procedure TTyRichApiGapsTest.TestPageSetupRoundTrips;
var
  d: TTyRichDocument;
  b, expect: TBytes;
  s: RawByteString;
  n: Integer;
  raised: Boolean;
begin
  Load(CBase);
  n := FRich.Document.UndoDepth;
  FRich.SetPageSetup(11906, 1440, 1080);
  AssertEquals('one step', n + 1, FRich.Document.UndoDepth);
  AssertEquals('the paper', 11906, FRich.Document.PaperWidth);
  AssertEquals('the text width', 11906 - 1440 - 1080, FRich.Document.TextWidthTwips);
  b := Saved;
  // the header's own words in their places, nothing else of the file changed
  s := AsRaw(FOriginal);
  s := StringReplace(s, BS + 'paperw12240', BS + 'paperw11906', []);
  s := StringReplace(s, BS + 'margl1800', BS + 'margl1440', []);
  s := StringReplace(s, BS + 'margr1800', BS + 'margr1080', []);
  expect := RawBytes(s);
  AssertTrue('only the page words changed: ' + AsRaw(b), SameBytes(expect, b));
  d := ReadBack(b);
  AssertEquals('the file: its paper', 11906, d.PaperWidth);
  AssertEquals('the file: its left margin', 1440, d.MarginLeft);
  AssertEquals('the file: its right margin', 1080, d.MarginRight);
  UndoGivesTheFileBack('SetPageSetup');
  // the same again: no step
  n := FRich.Document.UndoDepth;
  FRich.SetPageSetup(12240, 1800, 1800);
  AssertEquals('what it is: no step', n, FRich.Document.UndoDepth);
  // no room for text: refused, nothing changes
  raised := False;
  try
    FRich.SetPageSetup(2000, 1000, 1000);
  except
    on ETyRichEdit do raised := True;
  end;
  AssertTrue('no width left: refused', raised);
  AssertEquals('nothing changed', 12240, FRich.Document.PaperWidth);
  AssertEquals('no step', n, FRich.Document.UndoDepth);
  // a new document's page goes into its own header; ReadOnly does not stop code
  FRich.Clear;
  FRich.ReadOnly := True;
  FRich.SetPageSetup(10000, 500, 600);
  d := ReadBack(Saved);
  AssertEquals('a new document''s file: its paper', 10000, d.PaperWidth);
  AssertEquals('its left margin', 500, d.MarginLeft);
  AssertEquals('its right margin', 600, d.MarginRight);
end;

procedure TTyRichApiGapsTest.TestDefaultFormatsRoundTrip;
var
  d: TTyRichDocument;
  c: TTyCharFormat;
  p: TTyParaFormat;
  b: TBytes;
begin
  Load(CBase);
  c := TyDefaultCharFormat;
  c.FontName := 'Arial';
  c.Charset := 0;
  c.SizeHalfPt := 21;
  c.Style := [fsBold];
  p := TyDefaultParaFormat;
  p.SpaceAfter := 160;
  p.Align := paraCenter;
  TyRichSetLineMultiple(p, 1.08);
  FRich.SetDefaultFormats(c, p);
  AssertEquals('the document''s default size', 21, FRich.Document.DefaultCharFormat.SizeHalfPt);
  b := Saved;
  AssertTrue('the defaults in the header: ' + AsRaw(b), Has(b, '{' + BS + '*' + BS + 'defchp'));
  AssertTrue('the paragraph''s too', Has(b, '{' + BS + '*' + BS + 'defpap'));
  d := ReadBack(b);
  AssertEquals('the file: its default font', 'Arial', d.DefaultCharFormat.FontName);
  AssertEquals('the file: its default size', 21, d.DefaultCharFormat.SizeHalfPt);
  AssertTrue('the file: bold', fsBold in d.DefaultCharFormat.Style);
  p := d.Formats.ParaFormat(d.DefaultParaFormatId);
  AssertEquals('the file: space after', 160, p.SpaceAfter);
  AssertEquals('the file: centred', Ord(paraCenter), Ord(p.Align));
  AssertEquals('the file: 1.08 lines', Ord(lsMultiple), Ord(p.LineSpacing));
  AssertEquals('the file: 1.08 is 259', 259, p.LineSpacingValue);
  // what the file holds kept its look (the file's paragraphs have formats of their own)
  AssertEquals('the text: 12 pt still', 24, CF(FRich.Document, 0).SizeHalfPt);
  UndoGivesTheFileBack('SetDefaultFormats');
  // a document of plain paragraphs: they show in the new defaults
  FRich.Clear;
  FRich.Lines.Text := 'x';
  FRich.SetDefaultFormats(c, p);
  AssertEquals('a plain paragraph: the new default', 21, CF(FRich.Document, 0).SizeHalfPt);
  AssertEquals('and its paragraph format', FRich.Document.DefaultParaFormatId,
    FRich.Document.ParaFormatOf(0));
  d := ReadBack(Saved);
  AssertEquals('its file: the default size', 21, d.DefaultCharFormat.SizeHalfPt);
  FRich.Undo;
  AssertEquals('undone: the engine''s default', 0, CF(FRich.Document, 0).SizeHalfPt);
end;

procedure TTyRichApiGapsTest.TestDocumentColorRoundTrips;
var
  d: TTyRichDocument;
  b: TBytes;
begin
  Load(CBase);
  AssertEquals('none', clNone, FRich.DocumentColor);
  FRich.DocumentColor := TColor($00DAC0CC);
  AssertEquals('read back here', TColor($00DAC0CC), FRich.DocumentColor);
  b := Saved;
  AssertFalse('no \viewbksp: Word 16 writes the shape alone', Has(b, BS + 'viewbksp'));
  AssertTrue('the group as Word writes it', Has(b, CWord16Back(14336204)));
  AssertTrue('Word''s words: the background shape', Has(b, '{' + BS + '*' + BS + 'background'));
  AssertTrue('its fill, a COLORREF', Has(b, '{' + BS + 'sn fillColor}{' + BS + 'sv 14336204}'));
  d := ReadBack(b);
  AssertEquals('the file: the colour', TColor($00DAC0CC), d.DocumentColor);
  UndoGivesTheFileBack('DocumentColor');
  // clDefault and clWindow written are none
  FRich.DocumentColor := clDefault;
  AssertEquals('clDefault: none', clNone, FRich.DocumentColor);
  // a new document writes it in its own header
  FRich.Clear;
  FRich.DocumentColor := clNavy;
  d := ReadBack(Saved);
  AssertEquals('a new document''s file: the colour', clNavy, d.DocumentColor);
end;

procedure TTyRichApiGapsTest.TestApplyParagraphSpacingRoundTrips;
var
  d: TTyRichDocument;
  n: Integer;
begin
  Load(CBase);
  Sel(0, 0);
  n := FRich.Document.UndoDepth;
  AssertTrue('done', FRich.ApplyParagraphSpacing(6, 12));
  AssertEquals('one step', n + 1, FRich.Document.UndoDepth);
  d := ReadBack(Saved);
  AssertEquals('the file: 6 pt before', 120, PF(d, 0).SpaceBefore);
  AssertEquals('the file: 12 pt after', 240, PF(d, 0).SpaceAfter);
  AssertEquals('the file: the other paragraph as it was', 0, PF(d, 1).SpaceAfter);
  UndoGivesTheFileBack('ApplyParagraphSpacing');
  // a user's action: ReadOnly refuses it and nothing changes
  FRich.ReadOnly := True;
  n := FRich.Document.UndoDepth;
  AssertFalse('ReadOnly: refused', FRich.ApplyParagraphSpacing(6, 12));
  AssertEquals('no step', n, FRich.Document.UndoDepth);
  AssertEquals('nothing changed', 0, PF(FRich.Document, 0).SpaceBefore);
end;

procedure TTyRichApiGapsTest.TestLineSpacingMultipleRoundTrips;
var
  d: TTyRichDocument;
  b: TBytes;
begin
  // Word's default 1.08 (\sl259\slmult1): held, and the file as it was
  Load('{\rtf1\ansi\ansicpg1252\deff0{\fonttbl{\f0\fnil\fcharset0 Arial;}}'#13#10 +
    '\pard\sl259\slmult1\f0\fs24 One\par'#13#10 + '\pard Two\par'#13#10 + '}'#13#10);
  Sel(0, 0);
  AssertEquals('the rule', Ord(lsMultiple), Ord(FRich.Paragraph.LineSpacingRule));
  AssertEquals('the multiple', 259 / 240, FRich.Paragraph.LineSpacingMultiple, 1e-9);
  AssertEquals('nothing of it kept as words', 0, PF(FRich.Document, 0).Extra.Count);
  AssertEquals('a height: none', 0, FRich.Paragraph.LineSpacing);
  FRich.Paragraph.LineSpacingMultiple := 3;
  b := Saved;
  AssertTrue('written from the value: ' + AsRaw(b), Has(b, BS + 'sl720' + BS + 'slmult1'));
  d := ReadBack(b);
  AssertEquals('the file: 3 times', 3.0, TyRichLineMultiple(PF(d, 0)), 1e-9);
  UndoGivesTheFileBack('LineSpacingMultiple');
  // the four named ones keep their names
  Sel(0, 0);
  FRich.Paragraph.LineSpacingMultiple := 1.15;
  AssertEquals('1.15: named', Ord(ls115), Ord(PF(FRich.Document, 0).LineSpacing));
  AssertTrue('written as Word writes it', Has(Saved, BS + 'sl276' + BS + 'slmult1'));
  FRich.Paragraph.LineSpacingMultiple := 2;
  AssertEquals('2: double', Ord(lsDouble), Ord(PF(FRich.Document, 0).LineSpacing));
  FRich.Paragraph.LineSpacingMultiple := 0;
  AssertEquals('0: single', Ord(lsSingle), Ord(PF(FRich.Document, 0).LineSpacing));
  FRich.Paragraph.LineSpacingRule := lsMultiple;
  AssertEquals('the rule alone: single''s 1, named', Ord(lsSingle),
    Ord(PF(FRich.Document, 0).LineSpacing));
  // RichMemo's scale: 1.2 single, a multiple of its own on it too
  AssertEquals('RichMemo reads 1.25 x 1.2', 1.2 * 1.25, TyRichMetricOf(PF(ReadBack(
    RawBytes('{\rtf1\ansi\pard\sl300\slmult1 x\par}')), 0)).LineSpacing, 1e-9);
end;

procedure TTyRichApiGapsTest.TestPictureFromAGraphic;
var
  d: TTyRichDocument;
  bmp: TBitmap;
  obj: TTyRichObject;
  w, h: Integer;
  raised: Boolean;
begin
  Load(CBase);
  bmp := TBitmap.Create;
  try
    bmp.SetSize(20, 10);
    bmp.Canvas.Brush.Color := clRed;
    bmp.Canvas.FillRect(0, 0, 20, 10);
    // ReadOnly does not stop the command layer
    FRich.ReadOnly := True;
    AssertTrue('inserted', FRich.Document.Execute(TTyRichInsertPicture.Create(0, bmp)));
    obj := FRich.Document.ObjectAt(0);
    AssertTrue('a picture', obj is TTyRichPicture);
    AssertTrue('its size', obj.DisplaySize(w, h));
    AssertEquals('20 px at 96 dpi', 300, w);
    AssertEquals('10 px at 96 dpi', 150, h);
    d := ReadBack(Saved);
    obj := d.ObjectAt(0);
    AssertTrue('the file: a picture', obj is TTyRichPicture);
    AssertTrue('the file: its size', obj.DisplaySize(w, h));
    AssertEquals('the file: its width', 300, w);
    AssertEquals('the file: its height', 150, h);
    // (Undo is the user's: not under ReadOnly)
    FRich.ReadOnly := False;
    UndoGivesTheFileBack('TTyRichInsertPicture');
    // one side given: the other in proportion
    AssertTrue('inserted', FRich.Document.Execute(TTyRichInsertPicture.Create(0, bmp, 600)));
    AssertTrue('its size', FRich.Document.ObjectAt(0).DisplaySize(w, h));
    AssertEquals('600 wide: 300 high', 300, h);
  finally
    bmp.Free;
  end;
  // an empty graphic: a programmer's error, raised before anything changes
  bmp := TBitmap.Create;
  try
    raised := False;
    try
      FRich.Document.Execute(TTyRichInsertPicture.Create(0, bmp));
    except
      on ETyRichModel do raised := True;
    end;
    AssertTrue('an empty graphic raises', raised);
  finally
    bmp.Free;
  end;
end;

procedure TTyRichApiGapsTest.TestPictureFromAnImageList;
var
  d: TTyRichDocument;
  il: TImageList;
  bmp: TBitmap;
  obj: TTyRichObject;
  w, h: Integer;
  raised: Boolean;
begin
  Load(CBase);
  il := TImageList.Create(nil);
  bmp := TBitmap.Create;
  try
    il.Width := 16;
    il.Height := 16;
    bmp.SetSize(16, 16);
    bmp.Canvas.Brush.Color := clBlue;
    bmp.Canvas.FillRect(0, 0, 16, 16);
    il.Add(bmp, nil);
    bmp.Canvas.Brush.Color := clGreen;
    bmp.Canvas.FillRect(0, 0, 16, 16);
    il.Add(bmp, nil);
    AssertTrue('inserted', FRich.Document.Execute(TTyRichInsertPicture.Create(4, il, 1)));
    obj := FRich.Document.ObjectAt(4);
    AssertTrue('a picture', obj is TTyRichPicture);
    AssertTrue('its size', obj.DisplaySize(w, h));
    AssertEquals('16 px at 96 dpi', 240, w);
    AssertEquals('16 px at 96 dpi', 240, h);
    d := ReadBack(Saved);
    obj := d.ObjectAt(4);
    AssertTrue('the file: a picture', obj is TTyRichPicture);
    AssertTrue('the file: its size', obj.DisplaySize(w, h));
    AssertEquals('the file: its width', 240, w);
    // the image asked for, not another of the list's
    AssertTrue('image 0 too', FRich.Document.Execute(TTyRichInsertPicture.Create(5, il, 0)));
    AssertFalse('two images, two pictures', SameBytes(
      TTyRichPicture(FRich.Document.ObjectAt(4)).MakeImageData,
      TTyRichPicture(FRich.Document.ObjectAt(5)).MakeImageData));
    FRich.Undo;
    UndoGivesTheFileBack('TTyRichInsertPicture from an image list');
    raised := False;
    try
      FRich.Document.Execute(TTyRichInsertPicture.Create(0, il, 2));
    except
      on ETyRichModel do raised := True;
    end;
    AssertTrue('no such image: raised', raised);
    AssertFalse('nothing changed', FRich.Document.CanUndo);
  finally
    bmp.Free;
    il.Free;
  end;
end;

{ ---- what is drawn ---- }

procedure TTyRichApiGapsTest.TestTabLeaderIsDrawn;
var
  L: TTyParaLayout;
  bmp: TBGRABitmap;
  st: TTyRichPaintStyle;
  x, ink: Integer;
begin
  FRich.Lines.Text := 'a'#9'b';
  Sel(0, 0);
  FRich.Paragraph.SetTab(0, 72, rtaLeft, rtlDot);
  st := TyRichDefaultPaintStyle;
  bmp := TBGRABitmap.Create(200, 30, Sentinel);
  try
    L := Lay(FRich.Document, 0, 1000);
    L.Paint(bmp, 0, 0, Rect(0, 0, 200, 30), st, 0, 0);
    ink := 0;
    for x := 10 to 95 do
      if SamePx(st.TextColor, bmp.GetPixel(x, 15)) then Inc(ink);
    AssertEquals('dots every 5 pixels across the tab', 18, ink);
    AssertTrue('a gap between them', SamePx(Sentinel, bmp.GetPixel(11, 15)));
    // the leader written again: a line
    FRich.Paragraph.SetTab(0, 72, rtaLeft, rtlUnderline);
    bmp.FillRect(0, 0, 200, 30, Sentinel, dmSet);
    L := Lay(FRich.Document, 0, 1000);
    L.Paint(bmp, 0, 0, Rect(0, 0, 200, 30), st, 0, 0);
    ink := 0;
    for x := 10 to 95 do
      if SamePx(st.TextColor, bmp.GetPixel(x, 18)) then Inc(ink);
    AssertEquals('a line across the tab', 86, ink);
  finally
    bmp.Free;
  end;
end;

{ The shading is the file's colour, drawn as it is under the lines (not the space before), from
  the left indent to the right one; automatic text over it takes whichever of the theme's text
  colour and its opposite stands out more, a colour of its own stays. }
procedure TTyRichApiGapsTest.TestParagraphShadingIsDrawnAndAutomaticTextContrasts;
var
  d: TTyRichDocument;
  L: TTyParaLayout;
  bmp: TBGRABitmap;
  st: TTyRichPaintStyle;
  pfm: TTyParaFormat;
  f: TTyCharFormat;
  light, dark, red, navy: TBGRAPixel;

  procedure PaintWith(AText: TBGRAPixel; AShading: TColor);
  begin
    d := TTyRichDocument.CreateFromUtf8(RawBytes('abc def ghi'));
    FDocs.Add(d);
    pfm := TyDefaultParaFormat;
    pfm.Shading := AShading;
    pfm.SpaceBefore := 150;   // 10 px
    AssertTrue('shaded', d.Execute(TTyRichSetParaFormat.Create(0, 0, [pffShading,
      pffSpaceBefore], pfm)));
    f := TyDefaultCharFormat;
    f.Color := clRed;
    AssertTrue('red', d.Execute(TTyRichSetCharFormat.Create(TyRichRange(4, 3), [cffColor], f)));
    L := Lay(d, 0, 300);
    st := TyRichDefaultPaintStyle;
    st.TextColor := AText;
    bmp.FillRect(0, 0, bmp.Width, bmp.Height, Sentinel, dmSet);
    L.Paint(bmp, 0, 0, Rect(0, 0, bmp.Width, bmp.Height), st, 0, 0);
  end;

begin
  light := BGRA(230, 230, 230, 255);
  dark := BGRA(25, 25, 25, 255);
  red := PxOf(clRed);
  navy := PxOf(clNavy);
  bmp := TBGRABitmap.Create(340, 60, Sentinel);
  try
    // a light skin, a navy paragraph: the automatic text light
    PaintWith(dark, clNavy);
    AssertEquals('the layout''s shading', clNavy, L.Shading);
    AssertTrue('the ground under the line', SamePx(navy, bmp.GetPixel(250, 15)));
    AssertTrue('the space before stays clear', SamePx(Sentinel, bmp.GetPixel(250, 5)));
    AssertTrue('as far as the right indent', SamePx(navy, bmp.GetPixel(299, 15)));
    AssertTrue('not past it', SamePx(Sentinel, bmp.GetPixel(320, 15)));
    AssertTrue('automatic text: the opposite', SamePx(light, bmp.GetPixel(5, 18)));
    AssertTrue('a colour of its own: as it is', SamePx(red, bmp.GetPixel(50, 18)));
    AssertEquals('the document keeps automatic', clDefault,
      d.Formats.CharFormat(d.RunsOf(0)[0].Format).Color);
    // a dark skin over navy: the theme's own light text stands out already
    PaintWith(light, clNavy);
    AssertTrue('dark skin: the theme''s text', SamePx(light, bmp.GetPixel(5, 18)));
    // a light shading under a dark skin: the text dark
    PaintWith(light, clYellow);
    AssertTrue('yellow: the opposite', SamePx(dark, bmp.GetPixel(5, 18)));
    AssertTrue('yellow ground', SamePx(PxOf(clYellow), bmp.GetPixel(250, 15)));
    // no shading: nothing drawn under it
    PaintWith(dark, clNone);
    AssertTrue('no shading: the ground untouched', SamePx(Sentinel, bmp.GetPixel(250, 15)));
    AssertTrue('the theme''s text', SamePx(dark, bmp.GetPixel(5, 18)));
  finally
    bmp.Free;
  end;
end;

{ The document's ground replaces the theme's under the text, as the file has it; automatic text
  over it takes the contrasting colour; a highlight or a shading over it is what the text is
  on. clNone: the theme's ground again. }
procedure TTyRichApiGapsTest.TestDocumentColorWinsOverTheTheme;
var
  d: TTyRichDocument;
  L: TTyParaLayout;
  bmp: TBGRABitmap;
  st: TTyRichPaintStyle;
  f: TTyCharFormat;
  area: TRect;
  theme: TBGRAPixel;
begin
  // the control: its surface under the text
  FRich.Lines.Text := 'One'#13#10'Two';
  PaintAll;
  area := FRich.Area;
  theme := FRich.Surf.GetPixel(area.Right - 10, area.Bottom - 10);
  AssertFalse('the theme''s ground is not navy', SamePx(PxOf(clNavy), theme));
  FRich.DocumentColor := clNavy;
  PaintAll;
  AssertTrue('the document''s ground', SamePx(PxOf(clNavy),
    FRich.Surf.GetPixel(area.Right - 10, area.Bottom - 10)));
  AssertTrue('the paint style says it', FRich.Style.HasGround and (FRich.Style.Ground = clNavy));
  FRich.Undo;
  PaintAll;
  AssertTrue('undone: the theme''s again', SamePx(theme,
    FRich.Surf.GetPixel(area.Right - 10, area.Bottom - 10)));
  // automatic text over it
  d := TTyRichDocument.CreateFromUtf8(RawBytes('abc def ghi'));
  FDocs.Add(d);
  f := TyDefaultCharFormat;
  f.HighlightColor := clYellow;
  AssertTrue('highlight', d.Execute(TTyRichSetCharFormat.Create(TyRichRange(8, 3),
    [cffHighlight], f)));
  L := Lay(d, 0, 300);
  bmp := TBGRABitmap.Create(200, 30, Sentinel);
  try
    st := TyRichDefaultPaintStyle;
    st.TextColor := BGRA(25, 25, 25, 255);
    st.HasGround := True;
    st.Ground := clNavy;
    L.Paint(bmp, 0, 0, Rect(0, 0, 200, 30), st, 0, 0);
    AssertTrue('on navy: the light opposite', SamePx(BGRA(230, 230, 230, 255), bmp.GetPixel(5, 8)));
    AssertTrue('on its yellow highlight: the theme''s dark text',
      SamePx(BGRA(25, 25, 25, 255), bmp.GetPixel(85, 8)));
    st.HasGround := False;
    bmp.FillRect(0, 0, 200, 30, Sentinel, dmSet);
    L.Paint(bmp, 0, 0, Rect(0, 0, 200, 30), st, 0, 0);
    AssertTrue('no ground: the theme''s text', SamePx(BGRA(25, 25, 25, 255), bmp.GetPixel(5, 8)));
  finally
    bmp.Free;
  end;
end;

{ ---- Word's files ---- }

{ Word's page colour is the fill of the shape in {\*\background} (with \viewbksp1 or without); a paragraph's
  shading is \cbpat, with \cfpat mixed in by \shading. Read, and the file saved as it was. }
procedure TTyRichApiGapsTest.TestWordsShadingAndBackgroundAreRead;
var
  d: TTyRichDocument;
begin
  Load(CWordBack);
  d := FRich.Document;
  AssertEquals('the page colour', TColor(14336204), d.DocumentColor);
  AssertEquals('the fill', clYellow, PF(d, 0).Shading);
  AssertEquals('half the pattern''s black over white', RGBToColor(128, 128, 128), PF(d, 1).Shading);
  AssertEquals('none', clNone, PF(d, 2).Shading);
  AssertEquals('nothing of them kept as words', 0, PF(d, 0).Extra.Count + PF(d, 1).Extra.Count);
  // taken away: the background's group goes from the header, the rest stays
  FRich.DocumentColor := clNone;
  AssertFalse('no background written', Has(Saved, BS + 'background'));
  AssertTrue('the paragraphs as they were', Has(Saved, BS + 'pard' + BS + 'cbpat2' + BS + 'f0'));
  UndoGivesTheFileBack('DocumentColor in a file of Word''s');
end;

{ The facts of a file Word 16 wrote: its page colour the background shape alone (no
  \viewbksp), light green; a paragraph shaded \cbpat7 (yellow); a line 3 times its own height.
  Read, saved byte for byte; a colour set here is written as that group and reads back. }
procedure TTyRichApiGapsTest.TestWord16sPageColourFile;
var
  d: TTyRichDocument;
  b: TBytes;
begin
  Load('{\rtf1\ansi\ansicpg936\deff0{\fonttbl{\f0\fnil\fcharset0 Calibri;}}'#13#10 +
    '{\colortbl;\red0\green0\blue0;\red0\green0\blue255;\red0\green255\blue255;' +
    '\red0\green255\blue0;\red255\green0\blue255;\red255\green0\blue0;\red255\green255\blue0;}'#13#10 +
    '\paperw11906\paperh16838\margl1800\margr1800' + CWord16Back(12648384) + #13#10 +
    '\pard\cbpat7\f0\fs24 Yellow\par'#13#10 + '\pard\sl720\slmult1 Three times\par'#13#10 +
    '\pard\sl278\slmult1 Body\par'#13#10 + '}'#13#10);
  d := FRich.Document;
  AssertEquals('the page colour: C0 FF C0', TColor($C0FFC0), d.DocumentColor);
  AssertEquals('the shading: yellow', clYellow, PF(d, 0).Shading);
  AssertEquals('3 times', 3.0, TyRichLineMultiple(PF(d, 1)), 1e-9);
  AssertEquals('the template''s 1.16', 278, PF(d, 2).LineSpacingValue);
  // set on a document that had none: written as Word writes it, read back equal
  Load(CBase);
  FRich.DocumentColor := TColor($C0FFC0);
  b := Saved;
  AssertTrue('Word''s group: ' + AsRaw(b), Has(b, CWord16Back(12648384)));
  AssertFalse('no \viewbksp', Has(b, BS + 'viewbksp'));
  AssertEquals('read back', TColor($C0FFC0), ReadBack(b).DocumentColor);
  UndoGivesTheFileBack('a page colour set');
end;

{ A file of Word's: a change of a setting changes the header only where that setting is - the
  margin's word, the defaults' groups - and an undo gives the file's bytes back. }
procedure TTyRichApiGapsTest.TestAWordFilesHeaderChangesOnlyWhereTheSettingsAre;
var
  b: TBytes;
  s: RawByteString;
  d: TTyRichDocument;
  c: TTyCharFormat;
  p: TTyParaFormat;
begin
  b := FixtureBytes('word-zh.rtf');
  Load(AsRaw(b));
  AssertEquals('Word''s default size (its defchp)', 22, FRich.Document.DefaultCharFormat.SizeHalfPt);
  AssertEquals('Word''s default spacing (its defpap): 1.16', 278,
    FRich.Document.Formats.ParaFormat(FRich.Document.DefaultParaFormatId).LineSpacingValue);
  FRich.SetPageSetup(FRich.Document.PaperWidth, 1440, FRich.Document.MarginRight);
  s := StringReplace(AsRaw(FOriginal), BS + 'margl1800', BS + 'margl1440', []);
  AssertTrue('only the margin''s word', SameBytes(RawBytes(s), Saved));
  UndoGivesTheFileBack('a Word file''s page');
  // the defaults: Word's groups written again in their places
  c := FRich.Document.DefaultCharFormat;
  c.SizeHalfPt := 28;
  p := FRich.Document.Formats.ParaFormat(FRich.Document.DefaultParaFormatId);
  p.SpaceAfter := 0;
  FRich.SetDefaultFormats(c, p);
  d := ReadBack(Saved);
  AssertEquals('the file: the new default size', 28, d.DefaultCharFormat.SizeHalfPt);
  AssertEquals('the file: no space after', 0,
    d.Formats.ParaFormat(d.DefaultParaFormatId).SpaceAfter);
  AssertEquals('the file: one defchp', 1, Length(AsRaw(Saved)) - Length(StringReplace(AsRaw(Saved),
    'defchp', 'defch', [rfReplaceAll])));
  UndoGivesTheFileBack('a Word file''s defaults');
  // a page colour: added at the header's end, as Word 16 writes it
  FRich.DocumentColor := clSilver;
  d := ReadBack(Saved);
  AssertEquals('the file: the page colour', clSilver, d.DocumentColor);
  AssertTrue('the file: the paragraphs Word wrote', d.Text.ParaCount = FRich.Document.Text.ParaCount);
  UndoGivesTheFileBack('a Word file''s page colour');
end;

{ Any multiple of the line's own height, Word's rule (the rest below the text): SimSun 12 pt at
  3 times is 62.4 px at 96 PPI, its baseline 16.2 from the line's top; at Word's 1.08, 22.5.
  The named ones keep theirs (1.15: 23.9). Read from a file's \slN\slmult1. }
procedure TTyRichApiGapsTest.TestAnyMultipleIsLaidOutAsWordLaysItOut;
var
  lo: TTyRichLayouter;

  procedure Measure(ASl: Integer; AHeight, ABase: Double);
  var
    d: TTyRichDocument;
    st: TBytesStream;
    L: TTyParaLayout;
  begin
    d := TTyRichDocument.Create;
    FDocs.Add(d);
    st := TBytesStream.Create(RawBytes('{\rtf1\ansi\ansicpg936\deff0{\fonttbl{\f0\fcharset134 ' +
      'SimSun;}}\pard\sl' + IntToStr(ASl) + '\slmult1\f0\fs24 \''ba\''ba\''d7\''d6\par}'));
    try
      TyRichLoadRtf(d, st);
    finally
      st.Free;
    end;
    lo.Clear;
    L := lo.LayoutPara(d, 0, 4000, 96, 1);
    try
      AssertTrue(Format('%d: Word %.1f px high, here %d', [ASl, AHeight, L.Lines[0].Height]),
        Abs(L.Lines[0].Height - AHeight) <= 1.0);
      if ABase > 0 then
        AssertTrue(Format('%d: the baseline Word %.1f, here %d', [ASl, ABase,
          L.Lines[0].Baseline - L.Lines[0].Top]),
          Abs(L.Lines[0].Baseline - L.Lines[0].Top - ABase) <= 1.0);
    finally
      L.Release;
    end;
  end;

begin
  Need(['SimSun']);
  lo := TTyRichLayouter.Create(TTyRichBgraDevice.Create, True);
  try
    lo.BaseFontName := 'Arial';
    lo.BaseFontSizeHalfPt := 24;
    Measure(720, 62.4, 16.2);
    Measure(259, 22.5, 16.2);
    Measure(276, 23.9, 16.2);
  finally
    lo.Free;
  end;
end;

{ A file read on demand: what it holds keeps its look when the defaults change - a paragraph
  read before as much as one read after - and an undo gives everything back. }
procedure TTyRichApiGapsTest.TestALazyFileKeepsItsLookWhenTheDefaultsChange;
var
  d: TTyRichDocument;
  st: TBytesStream;
  c: TTyCharFormat;
  before, after: TTyCharFormatId;
  s: TTyRichDocSettings;
begin
  d := TTyRichDocument.Create;
  FDocs.Add(d);
  st := TBytesStream.Create(RawBytes(CBase));
  try
    TyRichLoadRtf(d, st);
  finally
    st.Free;
  end;
  AssertTrue('read on demand', d.Loader <> nil);
  before := d.RunsOf(0)[0].Format;
  AssertEquals('in the file''s default', d.DefaultCharFormatId, before);
  s := d.Settings;
  c := TyDefaultCharFormat;
  c.SizeHalfPt := 40;
  s.CharFormat := c;
  AssertTrue('changed', d.Execute(TTyRichChangeSettings.Create(s)));
  AssertEquals('the new default', 40, d.DefaultCharFormat.SizeHalfPt);
  after := d.RunsOf(0)[0].Format;
  AssertEquals('read before: its look kept', 24, d.Formats.CharFormat(after).SizeHalfPt);
  AssertEquals('read after: its look kept', 24, d.Formats.CharFormat(d.RunsOf(1)[0].Format).SizeHalfPt);
  d.Undo;
  AssertEquals('undone: the file''s default', 24, d.DefaultCharFormat.SizeHalfPt);
  AssertEquals('undone: the paragraph in it', d.DefaultCharFormatId, d.RunsOf(0)[0].Format);
end;

initialization
  RegisterTest(TTyRichApiGapsTest);

end.
