unit test.richedit.linemetrics;

{ How TTyRichEdit's layout measures a line, against what Word 16 does (measured on its own
  page, 12 pt = 16 px at 96 PPI):
  - a font's own line height H0 is its ascent, its descent and the line gap it asks for, the
    gap above the glyph box; an East Asian font (one whose code-page signature names a CJK
    code page) takes 1.3 times its ascent and descent instead, the added 0.3 half above and
    half below the glyph box (SimSun: 16 -> 20.8 px; Microsoft YaHei: 21.1 -> 27.5);
  - single spacing is H0; a multiple m is m x H0 with the text where single puts it and the
    rest below; "at least v" is max(H0, v) with the rest above; "exactly v" is v with the
    baseline at 0.8 v from the line's top;
  - the space before and after a paragraph stay outside its lines.
  Real fonts on the real device, so Windows only; a test whose font the machine lacks is
  ignored. Expected values are Word's, to a device pixel (the line of two fonts: the rule's,
  worked out from the fonts' design metrics). }

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  Classes, SysUtils, Math, fpcunit, testregistry,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.Commands,
  tyControls.RichEdit.RtfRead, tyControls.RichEdit.Layout;

type
  TTyRichLineMetricsTest = class(TTestCase)
  private
    FDocs: TFPList;
    FLayouter: TTyRichLayouter;
    FHeight, FBaseline, FParaHeight, FDescent: Integer;
    procedure Need(const AFonts: array of string);
    function NewDoc(const AText: UTF8String): TTyRichDocument;
    { Lays out one line of Chinese in AFont at AHalfPt with the spacing given; the line's
      height, its top-to-baseline and the paragraph's height land in the fields. }
    procedure Measure(const AFont: string; AHalfPt: Integer; ASpacing: TTyLineSpacing;
      AValueTwips: Integer = 0; ASpaceAfter: Integer = 0; APPI: Integer = 96;
      AZoom: Single = 1; const AText: UTF8String = '');
    procedure Near(const AWhat: string; AExpected: Double; AActual: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestSingleSpacingOfEastAsianFonts;
    procedure TestSingleSpacingOfLatinFonts;
    procedure TestALatinFontIsNotEastAsianByTheSystemsCharset;
    procedure TestMultipleSpacingPutsTheRestBelow;
    procedure TestAtLeastPutsTheRestAbove;
    procedure TestExactPutsTheBaselineAtFourFifths;
    procedure TestSpaceBeforeAndAfterStayOutside;
    procedure TestScalesWithPpiAndZoom;
    procedure TestTextAboveATableKeepsItsGap;
    procedure TestALineOfTwoFontsTakesTheEastAsianShareOfTheLargest;
  end;

implementation

const
  CHan = #$E6#$B1#$89#$E5#$AD#$97;   // two Han characters
  CLatin = 'Abg';

{$IFDEF MSWINDOWS}
type
  // GDI's LOGFONTW
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

{ A font family GDI has (no window: the screen's DC). }
function FontInstalled(const AName: string): Boolean;
var
  q: TFontQuery;
  dc: PtrUInt;
  w: UnicodeString;
  found: Boolean;
begin
  FillChar(q, SizeOf(q), 0);
  q.CharSet := 1;   // DEFAULT_CHARSET
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

procedure TTyRichLineMetricsTest.SetUp;
begin
  FDocs := TFPList.Create;
  FLayouter := TTyRichLayouter.Create(TTyRichBgraDevice.Create, True);
  FLayouter.BaseFontName := 'Arial';
  FLayouter.BaseFontSizeHalfPt := 24;
end;

procedure TTyRichLineMetricsTest.TearDown;
var
  i: Integer;
begin
  FLayouter.Free;
  FLayouter := nil;
  for i := 0 to FDocs.Count - 1 do TObject(FDocs[i]).Free;
  FDocs.Free;
end;

procedure TTyRichLineMetricsTest.Need(const AFonts: array of string);
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

function BytesOf(const S: RawByteString): TBytes;
begin
  Result := nil;
  SetLength(Result, Length(S));
  if Length(S) > 0 then Move(S[1], Result[0], Length(S));
end;

function TTyRichLineMetricsTest.NewDoc(const AText: UTF8String): TTyRichDocument;
begin
  Result := TTyRichDocument.CreateFromUtf8(BytesOf(AText));
  FDocs.Add(Result);
end;

procedure TTyRichLineMetricsTest.Measure(const AFont: string; AHalfPt: Integer;
  ASpacing: TTyLineSpacing; AValueTwips: Integer; ASpaceAfter: Integer; APPI: Integer;
  AZoom: Single; const AText: UTF8String);
var
  d: TTyRichDocument;
  f: TTyCharFormat;
  pf: TTyParaFormat;
  L: TTyParaLayout;
begin
  // Chinese in an East Asian font, Latin in a Latin one (else a fallback font joins the line)
  if AText = '' then d := NewDoc(CHan) else d := NewDoc(AText);
  f := TyDefaultCharFormat;
  f.FontName := AFont;
  f.SizeHalfPt := AHalfPt;
  AssertTrue('char format', d.Execute(TTyRichSetCharFormat.Create(TyRichRange(0, d.Text.Length),
    [cffFontName, cffSize], f)));
  pf := TyDefaultParaFormat;
  pf.LineSpacing := ASpacing;
  pf.LineSpacingValue := AValueTwips;
  pf.SpaceAfter := ASpaceAfter;
  AssertTrue('para format', d.Execute(TTyRichSetParaFormat.Create(0, 0,
    [pffLineSpacing, pffSpaceAfter], pf)));
  FLayouter.Clear;
  L := FLayouter.LayoutPara(d, 0, 4000, APPI, AZoom);
  try
    AssertEquals(AFont + ': one line', 1, L.LineCount);
    FHeight := L.Lines[0].Height;
    FBaseline := L.Lines[0].Baseline - L.Lines[0].Top;
    FParaHeight := L.Height;
    FDescent := L.Fragments[0].Descent;
  finally
    L.Release;
  end;
end;

procedure TTyRichLineMetricsTest.Near(const AWhat: string; AExpected: Double; AActual: Integer);
begin
  AssertTrue(Format('%s: Word %.1f px, here %d', [AWhat, AExpected, AActual]),
    Abs(AActual - AExpected) <= 1.0);
end;

{ SimSun and SimHei: an em of 16 px (ascent and descent; their own gap of 0.14 em is not
  Word's) times 1.3; Microsoft YaHei 1.32 em times 1.3; the added 0.3 half above the text. }
procedure TTyRichLineMetricsTest.TestSingleSpacingOfEastAsianFonts;
begin
  Need(['SimSun', 'SimHei', 'Microsoft YaHei']);
  Measure('SimSun', 24, lsSingle);
  Near('SimSun 12 pt', 20.8, FHeight);
  Near('SimSun 12 pt: its baseline', 16.2, FBaseline);
  Measure('SimHei', 24, lsSingle);
  Near('SimHei 12 pt', 20.8, FHeight);
  Measure('Microsoft YaHei', 24, lsSingle);
  Near('Microsoft YaHei 12 pt', 27.5, FHeight);
  Near('Microsoft YaHei 12 pt: its baseline', 20.2, FBaseline);
  Measure('SimSun', 18, lsSingle);
  Near('SimSun 9 pt', 15.6, FHeight);
  Measure('SimSun', 21, lsSingle);
  Near('SimSun 10.5 pt', 18.2, FHeight);
end;

{ A Latin font: ascent + descent + its line gap (GDI's external leading), the gap above. }
procedure TTyRichLineMetricsTest.TestSingleSpacingOfLatinFonts;
begin
  Need(['Arial', 'Times New Roman', 'Calibri']);
  Measure('Arial', 24, lsSingle, 0, 0, 96, 1, CLatin);
  Near('Arial 12 pt', 18.4, FHeight);
  Near('Arial 12 pt: its baseline below its gap', 15.0, FBaseline);
  Measure('Times New Roman', 24, lsSingle, 0, 0, 96, 1, CLatin);
  Near('Times New Roman 12 pt', 18.4, FHeight);
  Near('Times New Roman 12 pt: its baseline', 14.9, FBaseline);
  Measure('Calibri', 24, lsSingle, 0, 0, 96, 1, CLatin);
  Near('Calibri 12 pt', 19.5, FHeight);
  // Word's 1.15 em at 72 pt, where Arial's gap (3.2 px) is more than the tolerance
  Measure('Arial', 144, lsSingle, 0, 0, 96, 1, CLatin);
  Near('Arial 72 pt', 110.4, FHeight);
  Near('Arial 72 pt: its gap above the text', 90.0, FBaseline);
end;

{ East Asian is what the font declares (its code-page signature), not the charset GDI reports
  for it: on a Chinese system GDI reports GB2312 for Segoe UI, which declares no CJK code
  page - its line is its own 1.33 em, not 1.3 times that. }
procedure TTyRichLineMetricsTest.TestALatinFontIsNotEastAsianByTheSystemsCharset;
begin
  Need(['Segoe UI']);
  Measure('Segoe UI', 24, lsSingle, 0, 0, 96, 1, CLatin);
  Near('Segoe UI 12 pt', 21.3, FHeight);
end;

{ m x H0 (not m x the font size); the text stays where single spacing puts it. The model has
  no 3 x spacing (a multiple it has no name for is kept as written, not shown). }
procedure TTyRichLineMetricsTest.TestMultipleSpacingPutsTheRestBelow;
begin
  Need(['SimSun']);
  Measure('SimSun', 24, ls115);
  Near('1.15', 23.9, FHeight);
  Near('1.15: the text where single puts it', 16.2, FBaseline);
  Measure('SimSun', 24, ls15);
  Near('1.5', 31.2, FHeight);
  Near('1.5: the text where single puts it', 16.2, FBaseline);
  Measure('SimSun', 24, lsDouble);
  Near('double', 41.6, FHeight);
  Near('double: the text where single puts it', 16.2, FBaseline);
end;

procedure TTyRichLineMetricsTest.TestAtLeastPutsTheRestAbove;
begin
  Need(['SimSun']);
  Measure('SimSun', 24, lsAtLeast, 400);
  Near('at least 20 pt', 26.7, FHeight);
  Near('at least 20 pt: the rest above the text', 22.1, FBaseline);
  Measure('SimSun', 24, lsAtLeast, 200);
  Near('at least 10 pt: the font''s own', 20.8, FHeight);
  Near('at least 10 pt: its baseline', 16.2, FBaseline);
end;

procedure TTyRichLineMetricsTest.TestExactPutsTheBaselineAtFourFifths;
begin
  Need(['SimSun']);
  Measure('SimSun', 24, lsExact, 400);
  Near('exactly 20 pt', 26.7, FHeight);
  Near('exactly 20 pt: the baseline at 0.8', 21.3, FBaseline);
  Measure('SimSun', 24, lsExact, 240);
  Near('exactly 12 pt', 16.0, FHeight);
  Near('exactly 12 pt: the baseline at 0.8', 12.8, FBaseline);
end;

procedure TTyRichLineMetricsTest.TestSpaceBeforeAndAfterStayOutside;
begin
  Need(['SimSun']);
  Measure('SimSun', 24, lsSingle, 0, 120);
  Near('the line', 20.8, FHeight);
  Near('the paragraph: the line and 6 pt after it', 28.8, FParaHeight);
  Near('the baseline', 16.2, FBaseline);
end;

procedure TTyRichLineMetricsTest.TestScalesWithPpiAndZoom;
begin
  Need(['SimSun']);
  Measure('SimSun', 24, lsSingle, 0, 0, 144);
  Near('at 144 PPI', 31.2, FHeight);
  Measure('SimSun', 24, lsSingle, 0, 0, 96, 2);
  Near('at 200 %', 41.6, FHeight);
end;

{ The gap Word shows between a paragraph and the table under it is the paragraph's own line:
  from the bottom of its glyph box (the baseline and the font's descent) to the row's top,
  where the table's top border is. }
procedure TTyRichLineMetricsTest.TestTextAboveATableKeepsItsGap;

  function Gap(const ASpacing: RawByteString): Integer;
  const
    // the two Han characters in GB2312
    CHanGb: RawByteString = '\''ba\''ba\''d7\''d6';
  var
    d: TTyRichDocument;
    st: TBytesStream;
    L: TTyParaLayout;
    B: TTyBlockLayout;
    rtf: RawByteString;
  begin
    d := TTyRichDocument.Create;
    FDocs.Add(d);
    rtf := '{\rtf1\ansi\ansicpg936\deff0{\fonttbl{\f0\fcharset134 SimSun;}}';
    rtf := rtf + '\pard' + ASpacing + '\f0\fs24 ' + CHanGb + '\par';
    rtf := rtf + '\trowd\trgaph108\clbrdrt\brdrs\brdrw10 \cellx2000\pard\intbl\f0\fs24 x\cell\row';
    rtf := rtf + '\pard\par}';
    st := TBytesStream.Create(BytesOf(rtf));
    try
      TyRichLoadRtf(d, st);
    finally
      st.Free;
    end;
    FLayouter.Clear;
    B := FLayouter.LayoutBlock(d, 1, 4000, 96, 1);
    try
      AssertTrue('a row under the paragraph', B is TTyRowLayout);
    finally
      B.Release;
    end;
    L := FLayouter.LayoutPara(d, 0, 4000, 96, 1);
    try
      AssertEquals('one line', 1, L.LineCount);
      Result := L.Height - (L.Lines[0].Baseline + L.Fragments[0].Descent);
    finally
      L.Release;
    end;
  end;

begin
  Need(['SimSun']);
  Near('single: the glyph box to the border', 2.6, Gap(''));
  Near('double: the rest of the line below the text', 23.4, Gap('\sl480\slmult1'));
end;

{ A line of SimSun and Arial: the larger ascent and descent, Arial's gap, and the East Asian
  0.3 of SimSun's 16 px: 0.5 + 14.5 + 3.4 + 4.8 = 23.2, the baseline at 0.5 + 2.4 + 14.5. }
procedure TTyRichLineMetricsTest.TestALineOfTwoFontsTakesTheEastAsianShareOfTheLargest;
var
  d: TTyRichDocument;
  f: TTyCharFormat;
  L: TTyParaLayout;
begin
  Need(['SimSun', 'Arial']);
  d := NewDoc(CHan + 'Ab');
  f := TyDefaultCharFormat;
  f.FontName := 'SimSun';
  f.SizeHalfPt := 24;
  AssertTrue('SimSun', d.Execute(TTyRichSetCharFormat.Create(TyRichRange(0, 2),
    [cffFontName, cffSize], f)));
  f.FontName := 'Arial';
  AssertTrue('Arial', d.Execute(TTyRichSetCharFormat.Create(TyRichRange(2, 2),
    [cffFontName, cffSize], f)));
  L := FLayouter.LayoutPara(d, 0, 4000, 96, 1);
  try
    Near('the line', 23.2, L.Lines[0].Height);
    Near('its baseline', 17.4, L.Lines[0].Baseline - L.Lines[0].Top);
  finally
    L.Release;
  end;
end;

initialization
  RegisterTest(TTyRichLineMetricsTest);

end.
